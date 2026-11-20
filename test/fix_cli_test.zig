//! `selka fix`, `check` on library and test entries, and `test --diagnostics=json`,
//! driven through the compiler binary exactly as a user or an agent runs them.
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
        return self.runIn(null, command, target, args);
    }

    /// `run` in `environment` instead of the test process's own (null: its own).
    fn runIn(self: *const Project, environment: ?*const std.process.Environ.Map, command: []const u8, target: []const u8, args: []const []const u8) !Outcome {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
        defer testing.allocator.free(compiler);
        const absolute = try self.path(target);
        defer testing.allocator.free(absolute);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ compiler, command, absolute });
        try argv.appendSlice(testing.allocator, args);
        if (!std.mem.eql(u8, command, "test")) try argv.append(testing.allocator, self.cache);
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temp.dir }, .environ_map = environment });
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

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

const fixable_main =
    // migrate-embedded: skip intentional FIX-MIGRATION-1 missing mut call markers
    \\import util.helpers
    \\import util.unused
    \\
    \\
    \\func main() -> int:
    \\    mut xs: int[] = []
    \\    helpers.grow(xs)
    \\    helpers.grow(xs)
    \\    return len(xs)
    \\
;
const fixable_helpers =
    // migrate-embedded: skip intentional FIX-MIGRATION-1 retired module and append syntax
    \\module helpers
    \\
    \\public func grow(mut xs: int[]) -> Unit:
    \\    xs.append(1)
    \\
;
const unused_module =
    \\
    \\
    \\public func nothing() -> int:
    \\    return 0
    \\
;

// spec: FIX-MIGRATION-1
test "CLI fix applies every structured fix across modules to a fixed point" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = fixable_main },
        .{ .path = "util/helpers.selka", .data = fixable_helpers },
        .{ .path = "util/unused.selka", .data = unused_module },
    });
    defer project.deinit();
    // `--check` reports what would change and writes nothing.
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix util/helpers.selka: 1 edit (E_MODULE_HEADER)"));
    const untouched = try project.read("util/helpers.selka");
    defer testing.allocator.free(untouched);
    try testing.expectEqualStrings(fixable_helpers, untouched);
    // A real run removes the legacy module header, rewrites the retired `append`
    // method, marks both calls and drops the unused import.
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 3 edits (E_MUTATION_MARKER, W_UNUSED_IMPORT)"));
    try testing.expect(contains(fixed.stdout, "fixed util/helpers.selka: 2 edits (E_MODULE_HEADER, E_METHOD_REMOVED)"));
    try testing.expect(contains(fixed.stdout, "fix: 5 edits in 2 files over 3 rounds"));
    const main = try project.read("main.selka");
    defer testing.allocator.free(main);
    try testing.expectEqualStrings(
        \\import util.helpers
        \\
        \\
        \\func main() -> int:
        \\    mut xs: int[] = []
        \\    helpers.grow(mut xs)
        \\    helpers.grow(mut xs)
        \\    return len(xs)
        \\
    , main);
    // Nothing is left, and the project checks.
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

/// Require the project file at `path` to read exactly `wanted`.
fn expectFile(project: *const Project, path: []const u8, wanted: []const u8) !void {
    const actual = try project.read(path);
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(wanted, actual);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix removes the own markers that capability handles made redundant, and the program prints the same lines" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile("fixtures/fix-migration/capability-own/main.selka") },
        .{ .path = "state.selka", .data = @embedFile("fixtures/fix-migration/capability-own/state.selka") },
    });
    defer project.deinit();
    // Pre-5C code threads every capability with `own`: it still checks, with one warning per marker (`--warnings`: the
    // markers in `state.selka` are an imported module's, which `check FILE` otherwise counts in one line).
    const old = try project.run("check", "main.selka", &.{"--warnings"});
    defer old.deinit();
    try testing.expectEqual(@as(u8, 0), old.status);
    try testing.expectEqual(@as(usize, 14), std.mem.count(u8, old.stderr, "warning[W_CAPABILITY_OWN]"));
    const before = try project.run("run", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 0), before.status);
    try testing.expectEqualStrings("2 True\nproject 1 221\n", before.stdout);
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 8 edits (W_CAPABILITY_OWN)"));
    try testing.expect(contains(fixed.stdout, "fixed state.selka: 6 edits (W_CAPABILITY_OWN)"));
    try testing.expect(contains(fixed.stdout, "fix: 14 edits in 2 files over 1 round"));
    try expectFile(&project, "main.selka", @embedFile("fixtures/fix-migration/capability-own/main.expected.selka"));
    try expectFile(&project, "state.selka", @embedFile("fixtures/fix-migration/capability-own/state.expected.selka"));
    // The migrated project checks with no warning and prints what it printed before.
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning"));
    const after_run = try project.run("run", "main.selka", &.{});
    defer after_run.deinit();
    try testing.expectEqual(@as(u8, 0), after_run.status);
    try testing.expectEqualStrings(before.stdout, after_run.stdout);
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix names the case each ambiguous fail converted into, and leaves the ambiguous try as the one documented remainder" {
    const fixture = "fixtures/fix-migration/error-case-ambiguous/";
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile(fixture ++ "main.selka") },
        .{ .path = "errors.selka", .data = @embedFile(fixture ++ "errors.selka") },
    });
    defer project.deinit();
    // Before the one-case rule `fail "no name"`, `fail message` and the `try` picked the first `str` case, Parse.
    const old = try project.run("check", "main.selka", &.{});
    defer old.deinit();
    try testing.expectEqual(@as(u8, 1), old.status);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, old.stderr, "error[E_ERROR_CASE_AMBIGUOUS]: `try`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed errors.selka: 3 edits (E_ERROR_CASE_AMBIGUOUS, E_OWN_MARKER)"));
    try expectFile(&project, "errors.selka", @embedFile(fixture ++ "errors.expected.selka"));
    try expectFile(&project, "main.selka", @embedFile(fixture ++ "main.selka"));
    // The remainder is the `try` alone, which has no certain edit; its message shows the form.
    const remainder = try project.run("check", "main.selka", &.{});
    defer remainder.deinit();
    try testing.expectEqual(@as(u8, 1), remainder.status);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, remainder.stderr, "error["));
    try testing.expect(contains(remainder.stderr, "main.selka:4:15: error[E_ERROR_CASE_AMBIGUOUS]: `try` cannot convert the error: 2 cases of errors.AppErr"));
    try testing.expect(contains(remainder.stderr, "for example `fail errors.AppErr.Parse(value=error)` in its `Err(error)` arm"));
    // The hand edit that form describes checks, and the program prints what the old compiler's build printed.
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = @embedFile(fixture ++ "main.handedit.selka") });
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("AppErr.Parse(value='no name')\nAppErr.Parse(value='too long: abcdefghij')\nAppErr.Code(value=0)\n3\n" ++
        "AppErr.Parse(value='empty')\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix names the case an ambiguous fail converts into inside a generic function and through a generic union instance" {
    const original = @embedFile("fixtures/fix-migration/error-case-generic.selka");
    const expected = @embedFile("fixtures/fix-migration/error-case-generic.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    // Both `fail s` were refused with a message and no repair (a generic function) or a repair that did not build
    // (`Wrap[str].First(...)`); a generic union's case is built through its bare name.
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 2 edits (E_ERROR_CASE_AMBIGUOUS)"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 6 edits (E_ERROR_CASE_AMBIGUOUS, E_SINGLE_OWNER_BORROW)"));
    try expectFile(&project, "main.selka", expected);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    // Both functions fail on every call, so the program's status is the two failure arms: 7 and 30.
    const ran = try project.run("run", "main.selka", &.{"--print-result"});
    defer ran.deinit();
    try testing.expectEqualStrings("37\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix waits to rename a prelude-named function while a module that calls it does not parse, and names that module" {
    const root = "fixtures/fix-migration/builtin-function-unparsed/";
    var project = try Project.init(&.{
        .{ .path = "lib.selka", .data = @embedFile(root ++ "lib.selka") },
        .{ .path = "good.selka", .data = @embedFile(root ++ "good.selka") },
        .{ .path = "broken.selka", .data = @embedFile(root ++ "broken.selka") },
        .{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") },
    });
    defer project.deinit();
    // `broken.selka` calls `lib.len` and has a syntax error. A rename of `len` could not reach that call, so it would turn the parse
    // error into an unknown name once the file is repaired: `fix` applies none of it and says which file it waits for.
    const waiting = try project.run("fix", ".", &.{});
    defer waiting.deinit();
    try testing.expectEqual(@as(u8, 1), waiting.status);
    try testing.expect(contains(waiting.stderr, "selka fix: lib.selka: withheld E_BUILTIN_FUNCTION_NAME repairs: broken.selka does not parse and imports `lib`"));
    try testing.expect(contains(waiting.stderr, "repair broken.selka, then run `selka fix` again"));
    try testing.expect(contains(waiting.stderr, "broken.selka:6:1: error[E_EXPRESSION]"));
    try expectFile(&project, "lib.selka", @embedFile(root ++ "lib.selka"));
    try expectFile(&project, "good.selka", @embedFile(root ++ "good.selka"));
    // Once the file parses, one run renames the declaration and every qualified use, in all three modules together.
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "broken.selka", .data = @embedFile(root ++ "broken.handedit.selka") });
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed broken.selka: 1 edit (E_BUILTIN_FUNCTION_NAME)"));
    try testing.expect(contains(fixed.stdout, "fixed good.selka: 1 edit (E_BUILTIN_FUNCTION_NAME)"));
    try testing.expect(contains(fixed.stdout, "fixed lib.selka: 2 edits (E_BUILTIN_FUNCTION_NAME)"));
    try expectFile(&project, "lib.selka", @embedFile(root ++ "lib.expected.selka"));
    try expectFile(&project, "good.selka", @embedFile(root ++ "good.expected.selka"));
    try expectFile(&project, "broken.selka", @embedFile(root ++ "broken.expected.selka"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    // twice(1) is 4, good.use_good(2) is 3 and broken.use_broken(3) is 5.
    const ran = try project.run("run", "main.selka", &.{"--print-result"});
    defer ran.deinit();
    try testing.expectEqualStrings("12\n", ran.stdout);
}

test "CLI fix FR78 renames a prelude-named function with the calls that may be its own and leaves the builtin's call, so the file checks" {
    // A round-4 file server named its function `flush` and also called the builtin `flush(out)`. The old repair renamed that
    // call too, and the fixed file failed `E_TYPE` (expected int, found Stream).
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func flush(n: int) -> int:
        \\    return n
        \\
        \\func main(out: Stream) -> int:
        \\    flush(out)
        \\    print(out, "hi")
        \\    flush(out)
        \\    return flush(1) + flush(-2) + 4
        \\
    }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 3 edits (E_BUILTIN_FUNCTION_NAME)"));
    try expectFile(&project, "main.selka",
        \\func main_flush(n: int) -> int:
        \\    return n
        \\
        \\func main(out: Stream) -> int:
        \\    flush(out)
        \\    print(out, "hi")
        \\    flush(out)
        \\    return main_flush(1) + main_flush(-2) + 4
        \\
    );
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{"--print-result"});
    defer ran.deinit();
    try testing.expect(contains(ran.stdout, "3\n"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix waits to rename a type under a builtin type's name while a module that uses it does not parse" {
    const root = "fixtures/fix-migration/builtin-type-name/";
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") },
        .{ .path = "emit.selka", .data = @embedFile(root ++ "emit.selka") },
        .{ .path = "kicad/shape.selka", .data = @embedFile(root ++ "kicad/shape.selka") },
        .{ .path = "late.selka", .data = "import kicad.shape as sh\n\n\npublic func late() -> sh.Unit:\n    return sh.Unit(number=3" },
    });
    defer project.deinit();
    const waiting = try project.run("fix", ".", &.{});
    defer waiting.deinit();
    try testing.expectEqual(@as(u8, 1), waiting.status);
    try testing.expect(contains(waiting.stderr, "withheld E_BUILTIN_TYPE_NAME repairs: late.selka does not parse and imports `kicad.shape`"));
    try expectFile(&project, "kicad/shape.selka", @embedFile(root ++ "kicad/shape.selka"));
    try expectFile(&project, "emit.selka", @embedFile(root ++ "emit.selka"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix removes mut from capability parameters that nothing writes, down a call chain, and the program prints the same lines" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile("fixtures/fix-migration/capability-mut/main.selka") },
        .{ .path = "ops.selka", .data = @embedFile("fixtures/fix-migration/capability-mut/ops.selka") },
    });
    defer project.deinit();
    // Pre-5C code spells `mut` on every capability parameter its caller held in a `mut` binding. It checks, and the three
    // leaves warn: the two functions that pass their parameter on as `mut` do not, until their callee loses its own.
    // Some of the warnings are in `ops.selka`, so the checks name `--warnings` to print them all.
    const old = try project.run("check", "main.selka", &.{"--warnings"});
    defer old.deinit();
    try testing.expectEqual(@as(u8, 0), old.status);
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, old.stderr, "warning[W_CAPABILITY_MUT]"));
    const before = try project.run("run", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 0), before.status);
    try testing.expectEqualStrings("True False False\n0\n", before.stdout);
    // Each round removes the leaves' `mut`, then the call-site markers the callees no longer declare, which exposes the next
    // caller up the chain: six rounds for a chain of three. The parameter a function assigns keeps its `mut`, and so does
    // the parameter that is passed on to it.
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 8 edits (W_CAPABILITY_MUT, E_MUTATION_MARKER)"));
    try testing.expect(contains(fixed.stdout, "fixed ops.selka: 2 edits (W_CAPABILITY_MUT)"));
    try testing.expect(contains(fixed.stdout, "fix: 10 edits in 2 files over 6 rounds"));
    try expectFile(&project, "main.selka", @embedFile("fixtures/fix-migration/capability-mut/main.expected.selka"));
    try expectFile(&project, "ops.selka", @embedFile("fixtures/fix-migration/capability-mut/ops.expected.selka"));
    // The migrated project checks with no warning and prints what it printed before.
    const clean = try project.run("check", "main.selka", &.{"--warnings"});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning"));
    const after_run = try project.run("run", "main.selka", &.{});
    defer after_run.deinit();
    try testing.expectEqual(@as(u8, 0), after_run.status);
    try testing.expectEqualStrings(before.stdout, after_run.stdout);
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix drops the own and the copy from dicts.add and dicts.append_to keys, which borrow them now, and the program prints the same lines" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile("fixtures/fix-migration/dicts-own-key/main.selka") },
        .{ .path = "nets.selka", .data = @embedFile("fixtures/fix-migration/dicts-own-key/nets.selka") },
    });
    defer project.deinit();
    // The key was `own`, so the corpus writes `own key` for an owned local at its last use and `copy(key)` for a borrowed
    // one. Now an `own` marker there is refused, with the repair that removes it. `const net = copy(pin.net)` reads an element
    // of a list parameter, so its binding borrows the element and the copy goes too (case iii).
    const old = try project.run("check", "main.selka", &.{});
    defer old.deinit();
    try testing.expectEqual(@as(u8, 1), old.status);
    try testing.expect(contains(old.stderr, "but this argument is only read; remove `own`"));
    const before_preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer before_preview.deinit();
    try testing.expectEqual(@as(u8, 1), before_preview.status);
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 4 edits (E_OWN_MARKER, W_NEEDLESS_COPY)"));
    try testing.expect(contains(fixed.stdout, "fixed nets.selka: 2 edits (E_OWN_MARKER, W_NEEDLESS_COPY)"));
    try testing.expect(contains(fixed.stdout, "fix: 6 edits in 2 files over 2 rounds"));
    try expectFile(&project, "main.selka", @embedFile("fixtures/fix-migration/dicts-own-key/main.expected.selka"));
    try expectFile(&project, "nets.selka", @embedFile("fixtures/fix-migration/dicts-own-key/nets.expected.selka"));
    // The migrated project checks with no warning but the advice of `W_COPY_MOVE` (report only, with no fix: the loop over a
    // borrowed parameter could consume it if the parameter were `own`) and prints what the old spelling printed.
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning[W_NEEDLESS_COPY]"));
    try testing.expect(!contains(clean.stderr, "error"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("2 1 2 [1, 3] 2\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix repairs the copy of a value with no managed part to the bare value in one round (COPY-A1d)" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile("fixtures/fix-migration/plain-copy/main.selka") },
    });
    defer project.deinit();
    // The value is a record of numbers: the finding names the bare value, because `own` on it is `E_OWN_MARKER`.
    const warned = try project.run("check", "main.selka", &.{"--warnings"});
    defer warned.deinit();
    try testing.expect(contains(warned.stderr, "`fill` holds no managed value, so `copy(fill)` copies nothing a plain use would not: write `fill`"));
    try testing.expect(!contains(warned.stderr, "own fill"));
    // The finding of a cached check is the cold one's: the same lines before the summary, which counts the cached modules.
    const cached_warned = try project.run("check", "main.selka", &.{"--warnings"});
    defer cached_warned.deinit();
    try testing.expect(contains(cached_warned.stderr, "1 cached"));
    try testing.expectEqualStrings(warned.stderr[0..std.mem.indexOf(u8, warned.stderr, "check: ok").?], cached_warned.stderr[0..std.mem.indexOf(u8, cached_warned.stderr, "check: ok").?]);
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 1 edit (W_NEEDLESS_COPY)"));
    try testing.expect(contains(fixed.stdout, "fix: 1 edit in 1 file over 1 round"));
    try testing.expect(!contains(fixed.stderr, "E_OWN_MARKER"));
    try expectFile(&project, "main.selka", @embedFile("fixtures/fix-migration/plain-copy/main.expected.selka"));
    // The repaired project checks with no warning, and a second run changes nothing.
    const clean = try project.run("check", "main.selka", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning[W_NEEDLESS_COPY]"));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec: FIX-MIGRATION-1
test "CLI fix moves a value after the read of its length in the same call, with no copy, and then has nothing to fix (FR41)" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile("fixtures/fix-migration/read-first/main.selka") },
    });
    defer project.deinit();
    // The refusal names the move after the read, before the copy, and the repair is the one that moves.
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expect(contains(refused.stderr, "error[E_OWN_MARKER]"));
    try testing.expect(contains(refused.stderr, "write `mem=own plain` after `total=len(plain)` so that `plain` is read before it moves, or write `copy(plain)` to keep both"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "(E_OWN_MARKER, W_ELSE_IS_TRY)"));
    const text = try project.read("main.selka");
    defer testing.allocator.free(text);
    try testing.expect(!contains(text, "copy(plain)"));
    try expectFile(&project, "main.selka", @embedFile("fixtures/fix-migration/read-first/main.expected.selka"));
    // The repaired program checks with no warning, and a second run changes nothing.
    const clean = try project.run("check", "main.selka", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
    const again = try project.run("fix", "main.selka", &.{"--warnings"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expect(contains(again.stdout, "nothing to fix"));
}

// spec: FIX-MIGRATION-1
test "CLI fix reads a field first, moves two fields out with take or in one call, with no copy, then has nothing to fix (FR63, FR91B)" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile("fixtures/fix-migration/field-moves/main.selka") },
    });
    defer project.deinit();
    // Both refusals name the first move, and neither advises a copy first.
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expect(contains(refused.stderr, "write `flag=state.flag` before `lat=own state.lat` so that it is read before `state` is consumed, or write copy(...) to keep both"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "6 edits (E_SINGLE_OWNER_MOVED)"));
    try expectFile(&project, "main.selka", @embedFile("fixtures/fix-migration/field-moves/main.expected.selka"));
    const text = try project.read("main.selka");
    defer testing.allocator.free(text);
    try testing.expect(!contains(text, "copy("));
    // The repaired program checks, prints what the program means, and a second run changes nothing.
    const clean = try project.run("check", "main.selka", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expect(contains(ran.stdout, "3 True 2 1 True 12"));
    const again = try project.run("fix", "main.selka", &.{});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expect(contains(again.stdout, "nothing to fix"));
}

// spec: FIX-MIGRATION-1
test "CLI fix writes the own a loop gives away beside an overlap it cannot repair, and then prints that overlap (FR61)" {
    const fixture = "fixtures/fix-migration/own-beside-error/";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = @embedFile(fixture ++ "main.selka") }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stdout, "1 edit (E_OWN_MARKER)"));
    try testing.expect(contains(fixed.stderr, "main.selka:23:17: error[E_SINGLE_OWNER_OVERLAP]"));
    try expectFile(&project, "main.selka", @embedFile(fixture ++ "main.expected.selka"));
    // The overlap is the one refusal left, the one the marker written by hand leaves, and a second run changes nothing.
    const again = try project.run("fix", "main.selka", &.{});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 1), again.status);
    try testing.expect(contains(again.stdout, "nothing to fix"));
    try testing.expect(contains(again.stderr, "main.selka:23:17: error[E_SINGLE_OWNER_OVERLAP]"));
    try testing.expect(!contains(again.stderr, "E_OWN_MARKER"));
    try expectFile(&project, "main.selka", @embedFile(fixture ++ "main.expected.selka"));
}

// spec: FIX-MIGRATION-1
test "CLI fix repairs both borrows and both markers of a loop whose second borrow showed only once the marker was written (FR61)" {
    const fixture = "fixtures/fix-migration/own-beside-error/";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = @embedFile(fixture ++ "report-shape.selka") }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "(E_SINGLE_OWNER_BORROW, E_OWN_MARKER)"));
    try expectFile(&project, "main.selka", @embedFile(fixture ++ "report-shape.expected.selka"));
    const clean = try project.run("check", "main.selka", &.{"--no-cache"});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    const again = try project.run("fix", "main.selka", &.{});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expect(contains(again.stdout, "nothing to fix"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix repairs docstring examples on a prompt line and a continuation line to a passing selka test" {
    const original = @embedFile("fixtures/fix-migration/doc-example-own.selka");
    const expected = @embedFile("fixtures/fix-migration/doc-example-own.expected.selka");
    var project = try Project.init(&.{.{ .path = "app.selka", .data = original }});
    defer project.deinit();
    // The module checks, yet `selka test` refuses both examples, and the plain check says nothing.
    const refused = try project.run("test", "app.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stdout, "failed app::count.example"));
    try testing.expect(contains(refused.stdout, "failed app::greet.example"));
    const plain = try project.run("check", "app.selka", &.{});
    defer plain.deinit();
    try testing.expectEqual(@as(u8, 0), plain.status);
    // `--check` reports both docstring edits and writes nothing.
    const preview = try project.run("fix", "app.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix app.selka: 2 edits (E_OWN_MARKER)"));
    const untouched = try project.read("app.selka");
    defer testing.allocator.free(untouched);
    try testing.expectEqualStrings(original, untouched);
    // A real run changes exactly the two moved names; prompts and indentation stay.
    const fixed = try project.run("fix", "app.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "fixed app.selka: 2 edits (E_OWN_MARKER)"));
    const after = try project.read("app.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    // The examples now pass, and a second check finds nothing. `--force` runs them:
    // the per-user shared result store may already hold these exact examples, and a
    // reused result reads "cached", not "passed".
    const passing = try project.run("test", "app.selka", &.{"--force"});
    defer passing.deinit();
    try testing.expectEqual(@as(u8, 0), passing.status);
    try testing.expect(contains(passing.stdout, "2 passed"));
    const again = try project.run("fix", "app.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

const floor_doc = "public func floor(x: int) -> int:\n    \"\"\"Doubles x.\n\n    >>> floor(3)\n    6\n    \"\"\"\n    return x * 2\n";

test "CLI fix FR86 renames a prelude-named function with its only bare use, in its docstring example, in one round" {
    var project = try Project.init(&.{.{ .path = "app.selka", .data = floor_doc }});
    defer project.deinit();
    // Before FR86 the rename's edit in the example kept the overlay's offsets, past the file's end, and the run
    // repeated it for 200 rounds with the file unchanged.
    const fixed = try project.run("fix", "app.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "fix: 2 edits in 1 file over 1 round"));
    const after = try project.read("app.selka");
    defer testing.allocator.free(after);
    const renamed = try std.mem.replaceOwned(u8, testing.allocator, floor_doc, "floor(", "app_floor(");
    defer testing.allocator.free(renamed);
    try testing.expectEqualStrings(renamed, after);
    const passing = try project.run("test", "app.selka", &.{"--force"});
    defer passing.deinit();
    try testing.expectEqual(@as(u8, 0), passing.status);
    try testing.expect(contains(passing.stdout, "1 passed"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix leaves a docstring example whose repair cannot be mapped as written and reports it" {
    const original = @embedFile("fixtures/fix-migration/doc-example-unmapped.selka");
    const expected = @embedFile("fixtures/fix-migration/doc-example-unmapped.expected.selka");
    var project = try Project.init(&.{.{ .path = "app.selka", .data = original }});
    defer project.deinit();
    // The mappable own marker is applied; the two conditional-expression examples are not touched.
    const fixed = try project.run("fix", "app.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed app.selka: 1 edit (E_OWN_MARKER)"));
    try testing.expect(contains(fixed.stderr, "app.selka:26:24: error[E_CONDITIONAL_EXPRESSION_REMOVED]"));
    try testing.expect(contains(fixed.stderr, "app.selka:36:9: error[E_CONDITIONAL_EXPRESSION_REMOVED]"));
    try testing.expect(contains(fixed.stderr, "the repair edits text the docstring example does not hold verbatim"));
    const after = try project.read("app.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    // Nothing more is offered, and the refusals stay in the exit status.
    const again = try project.run("fix", "app.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 1), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
    const unchanged = try project.read("app.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(expected, unchanged);
}

test "CLI check --examples locates a refused example in its docstring with the repair as data" {
    const original = @embedFile("fixtures/fix-migration/doc-example-own.selka");
    var project = try Project.init(&.{.{ .path = "app.selka", .data = original }});
    defer project.deinit();
    const structured = try project.run("check", "app.selka", &.{ "--examples", "--diagnostics=json" });
    defer structured.deinit();
    try testing.expectEqual(@as(u8, 1), structured.status);
    try testing.expect(contains(structured.stderr, "\"code\":\"E_OWN_MARKER\""));
    try testing.expect(contains(structured.stderr, "\"start\":{\"line\":14,\"column\":27}"));
    try testing.expect(contains(structured.stderr, "\"start\":{\"line\":26,\"column\":28}"));
    try testing.expect(contains(structured.stderr, "\"text\":\"own \""));
    const text = try project.run("check", "app.selka", &.{"--examples"});
    defer text.deinit();
    try testing.expectEqual(@as(u8, 1), text.status);
    try testing.expect(contains(text.stderr, "app.selka:14:27: error[E_OWN_MARKER]"));
    try testing.expect(contains(text.stderr, "    >>> count(Holder(refs=refs))\n"));
    const repaired = try project.run("fix", "app.selka", &.{});
    defer repaired.deinit();
    try testing.expectEqual(@as(u8, 0), repaired.status);
    const ok = try project.run("check", "app.selka", &.{"--examples"});
    defer ok.deinit();
    try testing.expectEqual(@as(u8, 0), ok.status);
    try testing.expect(contains(ok.stderr, "check: ok (5 examples)"));
    // The pass is remembered per module, and a module whose bytes change is compiled again.
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = original });
    const stale = try project.run("check", "app.selka", &.{"--examples"});
    defer stale.deinit();
    try testing.expectEqual(@as(u8, 1), stale.status);
}

test "CLI check --examples leaves a graph with no example alone and checks a header-less file" {
    const original = @embedFile("fixtures/fix-migration/doc-example-own.selka");
    var project = try Project.init(&.{
        .{ .path = "plain.selka", .data = "public func one() -> int:\n    return 1\n" },
        .{ .path = "my-prog.selka", .data = original },
    });
    defer project.deinit();
    const none = try project.run("check", "plain.selka", &.{"--examples"});
    defer none.deinit();
    try testing.expectEqual(@as(u8, 0), none.status);
    try testing.expect(contains(none.stderr, "check: ok (0 examples)"));
    // A file name that is no module name is checked alone, as `selka test` checks it.
    const refused = try project.run("check", "my-prog.selka", &.{"--examples"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "my-prog.selka:14:27: error[E_OWN_MARKER]"));
    const fixed = try project.run("fix", "my-prog.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed my-prog.selka: 2 edits (E_OWN_MARKER)"));
    const passing = try project.run("test", "my-prog.selka", &.{});
    defer passing.deinit();
    try testing.expectEqual(@as(u8, 0), passing.status);
}

test "CLI fix migrates managed reversed hex once without nested copies" {
    const original = @embedFile("fixtures/fix-migration/reversed-managed.selka");
    const expected = @embedFile("fixtures/fix-migration/reversed-managed.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "fix: 2 edits in 1 file over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
    const native = try project.run("run", "main.selka", &.{});
    defer native.deinit();
    try testing.expectEqual(@as(u8, 0), native.status);
    try testing.expectEqualStrings("0000000000000000 00000000000000ab ffffffffffffffff\n", native.stdout);
    try testing.expectEqualStrings("", native.stderr);
}

const shared_import_test =
    \\import util.unused
    \\
    \\
    \\public func test_unused_is_empty() -> bool:
    \\    return unused.nothing() == 0
;

test "CLI fix over a directory with entries that share an import repairs them in one run" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = fixable_main },
        .{ .path = "util/helpers.selka", .data = fixable_helpers },
        .{ .path = "util/unused.selka", .data = unused_module },
        .{ .path = "first_test.selka", .data = shared_import_test },
        .{ .path = "second_test.selka", .data = shared_import_test },
    });
    defer project.deinit();
    // The two test entries import the module `main` no longer imports; every entry
    // is checked, and each repair is applied once.
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 3 edits (E_MUTATION_MARKER, W_UNUSED_IMPORT)"));
    try testing.expect(contains(fixed.stdout, "fixed util/helpers.selka: 2 edits (E_MODULE_HEADER, E_METHOD_REMOVED)"));
    try testing.expect(contains(fixed.stdout, "fix: 5 edits in 2 files over 3 rounds"));
    const first = try project.read("first_test.selka");
    defer testing.allocator.free(first);
    try testing.expectEqualStrings(shared_import_test, first);
    const again = try project.run("fix", ".", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

// spec-case: FRONTEND-MIGRATION-1
test "CLI fix migrates frontend syntax to a clean check and then reaches a fixed point" {
    const original = @embedFile("fixtures/fix-migration/frontend.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "func shift(mut points: Point[], named delta: int) -> Unit:"));
    try testing.expect(contains(after, "mut answer: int\n    if True:\n        answer = points[0].x\n    else:\n        answer = 0"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix renames a fallible parallel.map to parallel.map_results and keeps its meaning" {
    const original = @embedFile("fixtures/fix-migration/parallel-map-fallible.selka");
    const expected = @embedFile("fixtures/fix-migration/parallel-map-fallible.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_PARALLEL_MAP_FALLIBLE"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 2 edits (E_PARALLEL_MAP_FALLIBLE)"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

test "CLI fix repairs the removed spellings in the holes of a triple-quoted format string, on every line of it (F-19)" {
    // migrate-embedded: skip intentional removed method spellings in holes (F-19)
    const original =
        \\func main(out: Stream) -> int:
        \\    const name = "ada"
        \\    const page = f"""<ul>
        \\  <li>{name.upper()}</li>
        \\  <li class="x">{{name}} {name.strip()}</li>
        \\</ul>"""
        \\    const other = f'''line {name.lower()}
        \\  next {len(name)}'''
        \\    print(out, page, other)
        \\    return 0
        \\
    ;
    const expected =
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const name = "ada"
        \\    const page = f"""<ul>
        \\  <li>{strings.upper(name)}</li>
        \\  <li class="x">{{name}} {strings.strip(name)}</li>
        \\</ul>"""
        \\    const other = f'''line {strings.lower(name)}
        \\  next {len(name)}'''
        \\    print(out, page, other)
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix deletes a capability a task never reads, with the parameter it filled (W28)" {
    const original = @embedFile("fixtures/fix-migration/task-capability.selka");
    const expected = @embedFile("fixtures/fix-migration/task-capability.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_TASK_CAPABILITY"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "E_TASK_CAPABILITY"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix removes a generic from clause whose view sources cannot lend the result of an instance (lane HC)" {
    const original = @embedFile("fixtures/fix-migration/generic-from-view-source.selka");
    const expected = @embedFile("fixtures/fix-migration/generic-from-view-source.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_BORROW_SOURCE]: the instance `none_of[Inst]`"));
    try testing.expect(contains(refused.stderr, "error[E_BORROW_SOURCE]: the instance `none_of[List<i64>]`"));
    // The two instances share the one removal.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 1 edit (E_BORROW_SOURCE)"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix removes a from clause whose every source is a text or bytes view that cannot lend the result (lane CB)" {
    const original = @embedFile("fixtures/fix-migration/from-view-source.selka");
    const expected = @embedFile("fixtures/fix-migration/from-view-source.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_BORROW_SOURCE]"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 2 edits (E_BORROW_SOURCE)"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix removes a needless local copy and preserves the declared owning return" {
    const original = @embedFile("fixtures/fix-migration/needless-copy-borrows.selka");
    const expected = @embedFile("fixtures/fix-migration/needless-copy-borrows.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 1 edit (W_NEEDLESS_COPY)"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 1 edit (W_NEEDLESS_COPY)"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    // The repaired program checks without the warning, and nothing is left to fix.
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stdout, "W_NEEDLESS_COPY"));
    try testing.expect(!contains(checked.stderr, "W_NEEDLESS_COPY"));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes a dictionary key and a set member as the store that copies it only when new" {
    const original = @embedFile("fixtures/fix-migration/store-key-borrow.selka");
    const expected = @embedFile("fixtures/fix-migration/store-key-borrow.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 7 edits (W_NEEDLESS_COPY)"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 7 edits (W_NEEDLESS_COPY)"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    // The repaired program checks without the warning, and nothing is left to fix.
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stderr, "W_NEEDLESS_COPY"));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes sets.include for a lent value a set stores, in one round and without the copy it would rewrite" {
    const original = @embedFile("fixtures/fix-migration/set-store-lent.selka");
    const expected = @embedFile("fixtures/fix-migration/set-store-lent.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 7 edits (E_SINGLE_OWNER_BORROW, E_SINGLE_OWNER_OVERLAP)"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    // The seven stores took 21 edits over two rounds (a `copy(...)` each, then the needless-copy rewrite of it); now each is one
    // rename and the text is the same.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 7 edits (E_SINGLE_OWNER_BORROW, E_SINGLE_OWNER_OVERLAP)"));
    try testing.expect(contains(fixed.stdout, "over 1 round"));
    try testing.expect(!contains(fixed.stdout, "W_NEEDLESS_COPY"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    // The migrated program counts the distinct names each set holds.
    const ran = try project.run("run", "main.selka", &.{"--print-result"});
    defer ran.deinit();
    try testing.expectEqualStrings("17\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix rewrites a Result return clause to fails and keeps every call" {
    const original = @embedFile("fixtures/fix-migration/result-return.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_RESULT_RETURN_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "func read(text: str) -> int fails str:"));
    try testing.expect(contains(after, "fail \"empty\""));
    try testing.expect(contains(after, "func test_ok() -> bool fails str:"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix copies every borrowed return of a function that also returns a new value, every function in one round" {
    const original = @embedFile("fixtures/fix-migration/borrow-mixed.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_BORROW_MIXED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 8 edits (E_BORROW_MIXED)"));
    try testing.expect(contains(fixed.stdout, "fix: 8 edits in 1 file over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(@embedFile("fixtures/fix-migration/borrow-mixed.expected.selka"), after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
// FR59: `parallel.map` reads a slice or a list parameter in place, so only the owned parameter's slice is copied.
test "CLI fix copies a list slice an owned parameter takes, leaves parallel.map's as it is, and the result checks clean" {
    const original = @embedFile("fixtures/fix-migration/list-slice-own.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_SLICE_ESCAPES"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(@embedFile("fixtures/fix-migration/list-slice-own.expected.selka"), after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

/// A directory whose repairs take two rounds: `util.selka` exposes one marker per
/// round, and its test adds a third. `solo.selka` reads nothing they edit, so later
/// rounds reuse its first check.
const pooled_files = [_]File{
    .{ .path = "main.selka", .data = "import util\n\n\nfunc main(out: Stream) -> int:\n    mut rows: str[] = []\n    util.fill(mut rows)\n    print(out, len(rows))\n    return 0\n" },
    .{ .path = "util.selka", .data = "public func fill(mut rows: str[]):\n    const a = \"ab\" + \"cd\"\n    append(mut rows, a)\n    const b = \"ef\" + \"gh\"\n    append(mut rows, b)\n" },
    .{ .path = "util_test.selka", .data = "import util\n\n\npublic func test_fill() -> bool:\n    mut rows: str[] = []\n    util.fill(mut rows)\n    const c = \"x\" + \"y\"\n    append(mut rows, c)\n    return len(rows) == 3\n" },
    .{ .path = "solo.selka", .data = "public func twice(n: int) -> int:\n    return n * 2\n" },
};

/// Run `selka fix` on a whole project directory with `SELKA_JOBS` set.
fn fixWithJobs(project: *const Project, jobs: []const u8) !Outcome {
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_JOBS", jobs);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "fix", project.root, project.cache }, .cwd = .{ .dir = project.temp.dir }, .environ_map = &environment });
    return .{ .status = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .stdout = result.stdout, .stderr = result.stderr };
}

/// Expect one file to hold the same bytes in two projects.
fn expectSameFile(left: *const Project, right: *const Project, relative: []const u8) !void {
    const a = try left.read(relative);
    defer testing.allocator.free(a);
    const b = try right.read(relative);
    defer testing.allocator.free(b);
    try testing.expectEqualStrings(a, b);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix makes the same edits and report whether a directory's checks run on one worker or several" {
    var serial = try Project.init(&pooled_files);
    defer serial.deinit();
    var pooled = try Project.init(&pooled_files);
    defer pooled.deinit();
    const one = try fixWithJobs(&serial, "1");
    defer one.deinit();
    const many = try fixWithJobs(&pooled, "3");
    defer many.deinit();
    try testing.expectEqual(@as(u8, 0), one.status);
    try testing.expectEqual(@as(u8, 0), many.status);
    try testing.expectEqualStrings("fixed util.selka: 2 edits (E_OWN_MARKER)\nfixed util_test.selka: 1 edit (E_OWN_MARKER)\nfix: 3 edits in 2 files over 1 round\n", one.stdout);
    try testing.expectEqualStrings(one.stdout, many.stdout);
    try testing.expectEqualStrings(one.stderr, many.stderr);
    const util = try serial.read("util.selka");
    defer testing.allocator.free(util);
    try testing.expectEqualStrings("public func fill(mut rows: str[]):\n    const a = \"ab\" + \"cd\"\n    append(mut rows, own a)\n    const b = \"ef\" + \"gh\"\n    append(mut rows, own b)\n", util);
    try expectSameFile(&serial, &pooled, "main.selka");
    try expectSameFile(&serial, &pooled, "util.selka");
    try expectSameFile(&serial, &pooled, "util_test.selka");
    try expectSameFile(&serial, &pooled, "solo.selka");
    // A width of zero is refused before anything is checked.
    const refused = try fixWithJobs(&serial, "0");
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 2), refused.status);
    try testing.expect(contains(refused.stderr, "SELKA_JOBS must be a positive whole number"));
}

/// A project whose private `make_row` copies its parameter into the record it returns, and whose every caller (one in the
/// module, one in the test file) passes a new value: `W_COPY_FOR_STORE` declares the parameter `own`.
const own_store_files = [_]File{
    .{ .path = "main.selka", .data = "import rows\n\n\nfunc main(out: Stream) -> int:\n    const made = rows.pair()\n    write(out, f\"{made[0].name}\\n\")\n    return 0\n" },
    .{ .path = "rows.selka", .data = "public record Row:\n    name: str\n    size: int\n\n\nfunc make_row(name: str, size: int) -> Row:\n    return Row(name=copy(name), size=size)\n\n\n" ++
        "func label(text: str) -> str:\n    return f\"<{text}>\"\n\n\npublic func pair() -> Row[]:\n    return [make_row(\"alpha\", 1), make_row(label(\"beta\"), 2)]\n" },
    .{ .path = "rows_test.selka", .data = "import rows\n\n\npublic func test_make_row() -> bool:\n    return rows.make_row(\"gamma\", 3).size == 3\n" },
};

test "CLI fix declares a stored parameter own where every caller passes a new value, cold and cached alike, then has nothing to fix" {
    var cold = try Project.init(&own_store_files);
    defer cold.deinit();
    var warm = try Project.init(&own_store_files);
    defer warm.deinit();
    // The warning, cold and from a warm cache, is the same.
    const unchecked = try warm.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer unchecked.deinit();
    const first = try warm.run("check", ".", &.{"--warnings"});
    defer first.deinit();
    const cached = try warm.run("check", ".", &.{"--warnings"});
    defer cached.deinit();
    try testing.expect(contains(unchecked.stderr, "rows.selka:7:21: warning[W_COPY_FOR_STORE]: `make_row` copies parameter `name` into storage it keeps"));
    // Only the summary line's count of cached modules differs.
    const warning_end = std.mem.indexOf(u8, unchecked.stderr, "check: ok").?;
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], first.stderr[0..@min(warning_end, first.stderr.len)]);
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], cached.stderr[0..@min(warning_end, cached.stderr.len)]);
    try testing.expect(contains(cached.stderr, "check: ok (3 modules, 3 cached)"));
    // A check of the module alone does not hold the test file's caller: nothing.
    const alone = try warm.run("check", "rows.selka", &.{"--warnings"});
    defer alone.deinit();
    try testing.expect(!contains(alone.stderr, "W_COPY_FOR_STORE"));
    const fixed_cold = try fixWithJobs(&cold, "1");
    defer fixed_cold.deinit();
    const fixed_warm = try fixWithJobs(&warm, "1");
    defer fixed_warm.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_cold.status);
    try testing.expectEqualStrings("fixed rows.selka: 2 edits (W_COPY_FOR_STORE)\nfix: 2 edits in 1 file over 1 round\n", fixed_cold.stdout);
    try testing.expectEqualStrings(fixed_cold.stdout, fixed_warm.stdout);
    const rows = try cold.read("rows.selka");
    defer testing.allocator.free(rows);
    try testing.expect(contains(rows, "func make_row(own name: str, size: int) -> Row:\n    return Row(name=own name, size=size)\n"));
    try expectSameFile(&cold, &warm, "rows.selka");
    // No caller is edited: the test file is as it was.
    const callers = try cold.read("rows_test.selka");
    defer testing.allocator.free(callers);
    try testing.expectEqualStrings(own_store_files[2].data, callers);
    const clean = try cold.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
    const again = try fixWithJobs(&cold, "1");
    defer again.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

/// `own_store_files` with callers that pass `make_row` an owned local at its last use, one in the module and one in the test
/// file: the one repair also writes `own ` before each name, in both files (COPY-A3c).
const own_store_named_files = [_]File{
    own_store_files[0],
    .{ .path = "rows.selka", .data = "public record Row:\n    name: str\n    size: int\n\n\nfunc make_row(name: str, size: int) -> Row:\n    return Row(name=copy(name), size=size)\n\n\n" ++
        "public func pair() -> Row[]:\n    const text = f\"<{1}>\"\n    return [make_row(\"alpha\", 1), make_row(text, 2)]\n" },
    .{ .path = "rows_test.selka", .data = "import rows\n\n\npublic func test_make_row() -> bool:\n    const word = \"gam\" + \"ma\"\n    return rows.make_row(word, 3).size == 3\n" },
};

/// The diagnostics lines of a `--diagnostics=json` check (the summary line left out).
fn diagnosticLines(stderr: []const u8) []const u8 {
    const end = std.mem.lastIndexOf(u8, stderr, "\"kind\":\"diagnostic\"") orelse return "";
    return stderr[0 .. std.mem.indexOfScalarPos(u8, stderr, end, '\n') orelse stderr.len];
}

test "CLI fix declares a stored parameter own and marks the last-use names its callers pass, in two files, cold and cached alike" {
    var cold = try Project.init(&own_store_named_files);
    defer cold.deinit();
    var warm = try Project.init(&own_store_named_files);
    defer warm.deinit();
    const unchecked = try warm.run("check", ".", &.{ "--warnings", "--no-cache", "--diagnostics=json" });
    defer unchecked.deinit();
    const first = try warm.run("check", ".", &.{ "--warnings", "--diagnostics=json" });
    defer first.deinit();
    const cached = try warm.run("check", ".", &.{ "--warnings", "--diagnostics=json" });
    defer cached.deinit();
    try testing.expect(contains(unchecked.stderr, "{\"path\":\"rows.selka\",\"bytes\":{\"start\":63,\"end\":63},\"text\":\"own \"}," ++
        "{\"path\":\"rows.selka\",\"bytes\":{\"start\":113,\"end\":123},\"text\":\"own name\"}," ++
        "{\"path\":\"rows.selka\",\"bytes\":{\"start\":236,\"end\":236},\"text\":\"own \"}," ++
        "{\"path\":\"rows_test.selka\",\"bytes\":{\"start\":106,\"end\":106},\"text\":\"own \"}]"));
    try testing.expectEqualStrings(diagnosticLines(unchecked.stderr), diagnosticLines(first.stderr));
    try testing.expectEqualStrings(diagnosticLines(unchecked.stderr), diagnosticLines(cached.stderr));
    // The callee's body changes and the test file's caller stands in: its marks come from its stored answer.
    const edited = "public record Row:\n    name: str\n    size: int\n\n\nfunc make_row(name: str, size: int) -> Row:\n    return Row(name=copy(name), size=size + 0)\n\n\n" ++
        "public func pair() -> Row[]:\n    const text = f\"<{1}>\"\n    return [make_row(\"alpha\", 1), make_row(text, 2)]\n";
    try warm.temp.dir.writeFile(testing.io, .{ .sub_path = "rows.selka", .data = edited });
    const partial = try warm.run("check", ".", &.{ "--warnings", "--diagnostics=json" });
    defer partial.deinit();
    const partial_cold = try warm.run("check", ".", &.{ "--warnings", "--no-cache", "--diagnostics=json" });
    defer partial_cold.deinit();
    try testing.expect(contains(partial.stderr, "{\"path\":\"rows_test.selka\",\"bytes\":{\"start\":106,\"end\":106},\"text\":\"own \"}]"));
    try testing.expectEqualStrings(diagnosticLines(partial_cold.stderr), diagnosticLines(partial.stderr));
    try warm.temp.dir.writeFile(testing.io, .{ .sub_path = "rows.selka", .data = own_store_named_files[1].data });
    // `fix FILE` sets aside a repair with an edit in another file.
    const alone = try cold.run("fix", "rows.selka", &.{});
    defer alone.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", alone.stdout);
    const untouched = try cold.read("rows.selka");
    defer testing.allocator.free(untouched);
    try testing.expectEqualStrings(own_store_named_files[1].data, untouched);
    const fixed_cold = try fixWithJobs(&cold, "1");
    defer fixed_cold.deinit();
    const fixed_warm = try fixWithJobs(&warm, "1");
    defer fixed_warm.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_cold.status);
    try testing.expectEqualStrings("fixed rows.selka: 3 edits (W_COPY_FOR_STORE)\nfixed rows_test.selka: 1 edit (W_COPY_FOR_STORE)\nfix: 4 edits in 2 files over 1 round\n", fixed_cold.stdout);
    try testing.expectEqualStrings(fixed_cold.stdout, fixed_warm.stdout);
    const rows = try cold.read("rows.selka");
    defer testing.allocator.free(rows);
    try testing.expect(contains(rows, "func make_row(own name: str, size: int) -> Row:\n    return Row(name=own name, size=size)\n"));
    try testing.expect(contains(rows, "make_row(own text, 2)"));
    const callers = try cold.read("rows_test.selka");
    defer testing.allocator.free(callers);
    try testing.expect(contains(callers, "rows.make_row(own word, 3)"));
    try expectSameFile(&cold, &warm, "rows.selka");
    try expectSameFile(&cold, &warm, "rows_test.selka");
    const clean = try cold.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
    const again = try fixWithJobs(&cold, "1");
    defer again.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

/// A project whose private `names_of` copies a field of each element of its plain list parameter into the list it returns,
/// and whose callers (one in the module, one in the test file) pass an owned local at its last use: `W_COPY_FOR_STORE`
/// declares the parameter `own`, loops with `for r in own rows:` and marks both names. `sizes` copies a field of each
/// element of the list a call returns: a `W_NEEDLESS_COPY` repair inside the function (COPY-A2c).
const own_loop_files = [_]File{
    .{ .path = "main.selka", .data = "import rows\n\n\nfunc main(out: Stream) -> int:\n    write(out, f\"{rows.count()}\\n\")\n    return 0\n" },
    .{ .path = "rows.selka", .data = "public record Row:\n    name: str\n    size: int\n\n\nfunc names_of(rows: Row[]) -> str[]:\n    mut out: str[] = []\n    for r in rows:\n" ++
        "        append(mut out, copy(r.name))\n    return out\n\n\npublic func made() -> Row[]:\n    return [Row(name=\"a\", size=1), Row(name=\"b\", size=2)]\n\n\n" ++
        "func sizes() -> str[]:\n    mut out: str[] = []\n    for r in made():\n        append(mut out, copy(r.name))\n    return out\n\n\n" ++
        "public func count() -> int:\n    const all = made()\n    return len(names_of(all)) + len(sizes())\n" },
    .{ .path = "rows_test.selka", .data = "import rows\n\n\npublic func test_names_of() -> bool:\n    const some = rows.made()\n    return len(rows.names_of(some)) == 2\n" },
};

test "CLI fix declares a list parameter own, consumes it in its loop and marks the callers' names in two files, cold and cached alike" {
    var cold = try Project.init(&own_loop_files);
    defer cold.deinit();
    var warm = try Project.init(&own_loop_files);
    defer warm.deinit();
    const unchecked = try warm.run("check", ".", &.{ "--warnings", "--no-cache", "--diagnostics=json" });
    defer unchecked.deinit();
    const first = try warm.run("check", ".", &.{ "--warnings", "--diagnostics=json" });
    defer first.deinit();
    const cached = try warm.run("check", ".", &.{ "--warnings", "--diagnostics=json" });
    defer cached.deinit();
    try testing.expect(contains(unchecked.stderr, "`names_of` copies each element of parameter `rows` into storage it keeps"));
    // The hint the warning stands for is left out; the loop over the call's list is a repair, not a hint.
    try testing.expect(!contains(unchecked.stderr, "W_COPY_MOVE"));
    try testing.expectEqualStrings(diagnosticLines(unchecked.stderr), diagnosticLines(first.stderr));
    try testing.expectEqualStrings(diagnosticLines(unchecked.stderr), diagnosticLines(cached.stderr));
    // A check of the module alone does not hold the test file's caller: the hint, and no warning.
    const alone = try warm.run("check", "rows.selka", &.{"--warnings"});
    defer alone.deinit();
    try testing.expect(!contains(alone.stderr, "W_COPY_FOR_STORE"));
    try testing.expect(contains(alone.stderr, "W_COPY_MOVE"));
    const fixed_cold = try fixWithJobs(&cold, "1");
    defer fixed_cold.deinit();
    const fixed_warm = try fixWithJobs(&warm, "1");
    defer fixed_warm.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_cold.status);
    try testing.expectEqualStrings("fixed rows.selka: 6 edits (W_COPY_FOR_STORE, W_NEEDLESS_COPY)\nfixed rows_test.selka: 1 edit (W_COPY_FOR_STORE)\n" ++
        "fix: 7 edits in 2 files over 1 round\n", fixed_cold.stdout);
    try testing.expectEqualStrings(fixed_cold.stdout, fixed_warm.stdout);
    const rows = try cold.read("rows.selka");
    defer testing.allocator.free(rows);
    try testing.expect(contains(rows, "func names_of(own rows: Row[]) -> str[]:\n    mut out: str[] = []\n    for r in own rows:\n        append(mut out, own r.name)\n"));
    try testing.expect(contains(rows, "    for r in own made():\n        append(mut out, own r.name)\n"));
    try testing.expect(contains(rows, "names_of(own all)"));
    const callers = try cold.read("rows_test.selka");
    defer testing.allocator.free(callers);
    try testing.expect(contains(callers, "rows.names_of(own some)"));
    try expectSameFile(&cold, &warm, "rows.selka");
    try expectSameFile(&cold, &warm, "rows_test.selka");
    const clean = try cold.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
    const again = try fixWithJobs(&cold, "1");
    defer again.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

/// `own_store_files` with `make_row` `public`: its callers are all in the project (COPY-A3d).
const public_store_files = [_]File{
    own_store_files[0],
    .{ .path = "rows.selka", .data = "public record Row:\n    name: str\n    size: int\n\n\npublic func make_row(name: str, size: int) -> Row:\n    return Row(name=copy(name), size=size)\n\n\n" ++
        "func label(text: str) -> str:\n    return f\"<{text}>\"\n\n\npublic func pair() -> Row[]:\n    return [make_row(\"alpha\", 1), make_row(label(\"beta\"), 2)]\n" },
    own_store_files[2],
};

test "CLI fix also declares a stored parameter of a public function own in a project that is no package, cold and cached alike" {
    var cold = try Project.init(&public_store_files);
    defer cold.deinit();
    // `interface_files: false` is the default: the same project with it spelled out is repaired the same way.
    var warm = try Project.init(&(public_store_files ++ [_]File{.{ .path = "selka.json", .data = "{\"version\": 1, \"interface_files\": false}" }}));
    defer warm.deinit();
    const unchecked = try warm.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer unchecked.deinit();
    const first = try warm.run("check", ".", &.{"--warnings"});
    defer first.deinit();
    const cached = try warm.run("check", ".", &.{"--warnings"});
    defer cached.deinit();
    try testing.expect(contains(unchecked.stderr, "rows.selka:7:21: warning[W_COPY_FOR_STORE]: `make_row` copies parameter `name` into storage it keeps, " ++
        "and no caller needs the value after the call: declare it `own name` and the function keeps that value rather than a copy; " ++
        "`make_row` is public, so its signature changes"));
    const warning_end = std.mem.indexOf(u8, unchecked.stderr, "check: ok").?;
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], first.stderr[0..@min(warning_end, first.stderr.len)]);
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], cached.stderr[0..@min(warning_end, cached.stderr.len)]);
    try testing.expect(contains(cached.stderr, "check: ok (3 modules, 3 cached)"));
    // A check of the module alone does not hold every caller: no warning.
    const alone = try warm.run("check", "rows.selka", &.{"--warnings"});
    defer alone.deinit();
    try testing.expect(!contains(alone.stderr, "W_COPY_FOR_STORE"));
    const fixed_cold = try fixWithJobs(&cold, "1");
    defer fixed_cold.deinit();
    const fixed_warm = try fixWithJobs(&warm, "1");
    defer fixed_warm.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_cold.status);
    try testing.expectEqualStrings("fixed rows.selka: 2 edits (W_COPY_FOR_STORE)\nfix: 2 edits in 1 file over 1 round\n", fixed_cold.stdout);
    try testing.expectEqualStrings(fixed_cold.stdout, fixed_warm.stdout);
    const rows = try cold.read("rows.selka");
    defer testing.allocator.free(rows);
    try testing.expect(contains(rows, "public func make_row(own name: str, size: int) -> Row:\n    return Row(name=own name, size=size)\n"));
    try expectSameFile(&cold, &warm, "rows.selka");
    const clean = try cold.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
    const again = try fixWithJobs(&cold, "1");
    defer again.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

/// A project of one namespace, `numbers.selka` and `numbers/more.selka`: the shape of a package root (`selka packages lock`), whose
/// `public` `make` another project may call from outside this check.
const package_shaped_files = [_]File{
    .{ .path = "selka.json", .data = "{\"version\": 1}" },
    .{ .path = "numbers.selka", .data = "public record Row:\n    name: str\n\n\npublic func make(name: str) -> Row:\n    return Row(name=copy(name))\n" },
    .{ .path = "numbers/more.selka", .data = "import numbers\n\n\npublic func again() -> numbers.Row:\n    return numbers.make(\"x\")\n" },
};

test "CLI fix keeps the public signatures of a package-shaped project and of one with interface_files, as it printed them before" {
    var package = try Project.init(&package_shaped_files);
    defer package.deinit();
    var publishing = try Project.init(&(public_store_files ++ [_]File{.{ .path = "selka.json", .data = "{\"version\": 1, \"interface_files\": true}" }}));
    defer publishing.deinit();
    for ([_]*const Project{ &package, &publishing }) |project| {
        const cold = try project.run("check", ".", &.{ "--warnings", "--no-cache" });
        defer cold.deinit();
        const first = try project.run("check", ".", &.{"--warnings"});
        defer first.deinit();
        const cached = try project.run("check", ".", &.{"--warnings"});
        defer cached.deinit();
        try testing.expect(!contains(cold.stderr, "W_COPY_FOR_STORE"));
        try testing.expect(!contains(first.stderr, "W_COPY_FOR_STORE"));
        try testing.expect(!contains(cached.stderr, "W_COPY_FOR_STORE"));
        const fixed = try fixWithJobs(project, "1");
        defer fixed.deinit();
        try testing.expect(!contains(fixed.stdout, "W_COPY_FOR_STORE"));
    }
    // The package checks clean and has nothing to fix; the project with interface files is refused for its missing files, as ever.
    const checked = try package.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const nothing = try fixWithJobs(&package, "1");
    defer nothing.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", nothing.stdout);
    const stale = try publishing.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer stale.deinit();
    try testing.expect(contains(stale.stderr, "E_INTERFACE_FILE_STALE"));
    const numbers = try package.read("numbers.selka");
    defer testing.allocator.free(numbers);
    try testing.expectEqualStrings(package_shaped_files[1].data, numbers);
    const rows = try publishing.read("rows.selka");
    defer testing.allocator.free(rows);
    try testing.expectEqualStrings(public_store_files[1].data, rows);
}

/// The package-shaped files without their `selka.json`. `selka check DIR` takes the directory as the root of every file
/// beneath it, so `numbers/more.selka` is the module `numbers.more` and its `import numbers` finds `numbers.selka`; a run of `fix`
/// used to check `numbers/more.selka` on its own, with `numbers/` as its root, and refused it with `E_MODULE_READ`.
const unconfigured_nested_files = [_]File{ package_shaped_files[1], package_shaped_files[2] };

test "CLI fix reads a folder below a directory with no selka.json as check DIR does, and has nothing of its own to say" {
    var project = try Project.init(&unconfigured_nested_files);
    defer project.deinit();
    const checked = try project.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const fixed = try fixWithJobs(&project, "1");
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", fixed.stdout);
    try testing.expectEqualStrings("", fixed.stderr);
    try expectFile(&project, "numbers.selka", unconfigured_nested_files[0].data);
    try expectFile(&project, "numbers/more.selka", unconfigured_nested_files[1].data);
}

test "CLI fix repairs a module in a folder below a directory with no selka.json, and the directory then checks" {
    var project = try Project.init(&.{
        unconfigured_nested_files[0],
        .{ .path = "numbers/more.selka", .data = "public func again() -> numbers.Row:\n    return numbers.make(\"x\")\n" },
    });
    defer project.deinit();
    const refused = try project.run("check", ".", &.{"--no-cache"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "numbers/more.selka:1:24: error[E_MODULE_NOT_IMPORTED]"));
    const fixed = try fixWithJobs(&project, "1");
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed numbers/more.selka: 1 edit (E_MODULE_NOT_IMPORTED)\nfix: 1 edit in 1 file over 1 round\n", fixed.stdout);
    try testing.expectEqualStrings("", fixed.stderr);
    try expectFile(&project, "numbers/more.selka", "import numbers\n\npublic func again() -> numbers.Row:\n    return numbers.make(\"x\")\n");
    const checked = try project.run("check", ".", &.{"--no-cache"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

test "CLI fix still checks each program of a folder of independent programs with its own folder as root" {
    // `check DIR` refuses this folder (`helper` is not under the directory), so it is no project: every file is an entry of
    // its own, as ever, and `fix` has nothing to say about two programs that each check.
    const program = "import helper\n\n\nfunc main() -> int:\n    return helper.twice(2)\n";
    const helper = "public func twice(number: int) -> int:\n    return number * 2\n";
    var project = try Project.init(&.{
        .{ .path = "one/main.selka", .data = program },
        .{ .path = "one/helper.selka", .data = helper },
        .{ .path = "two/main.selka", .data = program },
        .{ .path = "two/helper.selka", .data = helper },
    });
    defer project.deinit();
    const refused = try project.run("check", ".", &.{"--no-cache"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "E_MODULE_READ"));
    const fixed = try fixWithJobs(&project, "1");
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", fixed.stdout);
    try testing.expectEqualStrings("", fixed.stderr);
}

/// A project whose private `tag_of` returns `None` or a copy of a place of its parameter, and whose callers (one in the
/// module, one in the test file) only read the result: `W_COPY_RETURNED` declares it `from row`. The private `pick` copies a
/// place too, but its caller `label` returns the result, which `from row` would refuse there: the hint stays. `name_of` is
/// named as a value, so `from row` is refused whatever its callers do: no hint.
const returned_files = [_]File{
    .{ .path = "main.selka", .data = "import rows\n\n\nfunc main(out: Stream) -> int:\n    const row = rows.Row(name=\"a\", tags=[\"b\"])\n    write(out, f\"{rows.first_tag(row)} {rows.label(row)}\\n\")\n    return 0\n" },
    .{ .path = "rows.selka", .data = "public record Row:\n    name: str\n    tags: str[]\n\n\nfunc tag_of(row: Row) -> str?:\n    if len(row.tags) == 0:\n        return None\n    return Some(copy(row.tags[0]))\n\n\n" ++
        "public func first_tag(row: Row) -> int:\n    const tag = tag_of(row) else:\n        return 0\n    return len(tag)\n\n\n" ++
        "func pick(row: Row) -> str:\n    return copy(row.name)\n\n\npublic func label(row: Row) -> str:\n    return pick(row)\n\n\n" ++
        "func name_of(row: Row) -> str:\n    return copy(row.name)\n\n\npublic func name_size(row: Row) -> int:\n    const read = name_of\n    return len(read(row))\n" },
    .{ .path = "rows_test.selka", .data = "import rows\n\n\npublic func test_tag_of() -> bool:\n    const row = rows.Row(name=\"a\", tags=[])\n    return rows.tag_of(row) is None\n" },
};

test "CLI fix declares a result from the parameter whose places every return copies, cold and cached alike, then has nothing to fix" {
    var cold = try Project.init(&returned_files);
    defer cold.deinit();
    var warm = try Project.init(&returned_files);
    defer warm.deinit();
    const unchecked = try warm.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer unchecked.deinit();
    const first = try warm.run("check", ".", &.{"--warnings"});
    defer first.deinit();
    const cached = try warm.run("check", ".", &.{"--warnings"});
    defer cached.deinit();
    try testing.expect(contains(unchecked.stderr, "rows.selka:9:17: warning[W_COPY_RETURNED]: every return of `tag_of` copies a place of `row`, and no caller keeps the result"));
    // The warning stands for the hint at its place; `pick`'s hint stays, for `label` returns its result.
    try testing.expect(!contains(unchecked.stderr, "every return of `tag_of` copies a place of `row`: if every caller"));
    try testing.expect(contains(unchecked.stderr, "rows.selka:19:12: warning[W_COPY_MOVE]: every return of `pick` copies a place of `row`"));
    try testing.expect(!contains(unchecked.stderr, "W_COPY_RETURNED]: every return of `pick`"));
    // `name_of` is named as a value, which a `from` result cannot be: neither the warning nor the hint.
    try testing.expect(!contains(unchecked.stderr, "every return of `name_of`"));
    // Only the summary line's count of cached modules differs.
    const warning_end = std.mem.indexOf(u8, unchecked.stderr, "check: ok").?;
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], first.stderr[0..@min(warning_end, first.stderr.len)]);
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], cached.stderr[0..@min(warning_end, cached.stderr.len)]);
    try testing.expect(contains(cached.stderr, "check: ok (3 modules, 3 cached)"));
    // A check of the module alone does not hold the test file's caller: the hint, no repair.
    const alone = try warm.run("check", "rows.selka", &.{"--warnings"});
    defer alone.deinit();
    try testing.expect(!contains(alone.stderr, "W_COPY_RETURNED"));
    try testing.expect(contains(alone.stderr, "every return of `tag_of` copies a place of `row`: if every caller"));
    const fixed_cold = try fixWithJobs(&cold, "1");
    defer fixed_cold.deinit();
    const fixed_warm = try fixWithJobs(&warm, "1");
    defer fixed_warm.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_cold.status);
    try testing.expectEqualStrings("fixed rows.selka: 2 edits (W_COPY_RETURNED)\nfix: 2 edits in 1 file over 1 round\n", fixed_cold.stdout);
    try testing.expectEqualStrings(fixed_cold.stdout, fixed_warm.stdout);
    const rows = try cold.read("rows.selka");
    defer testing.allocator.free(rows);
    try testing.expect(contains(rows, "func tag_of(row: Row) -> str? from row:\n    if len(row.tags) == 0:\n        return None\n    return Some(row.tags[0])\n"));
    try testing.expect(contains(rows, "func pick(row: Row) -> str:\n    return copy(row.name)\n"));
    try expectSameFile(&cold, &warm, "rows.selka");
    // No caller is edited.
    const callers = try cold.read("rows_test.selka");
    defer testing.allocator.free(callers);
    try testing.expectEqualStrings(returned_files[2].data, callers);
    const clean = try cold.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "W_COPY_RETURNED"));
    try testing.expect(!contains(clean.stderr, "every return of `tag_of`"));
    try testing.expect(contains(clean.stderr, "every return of `pick`"));
    const again = try fixWithJobs(&cold, "1");
    defer again.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

/// A project of three namespaces (`main`, `rows`, `rows_test`: no package root could hold it) whose `public` functions copy a
/// place of their parameter (COPY-FROM-PUBLIC). `tag_of`'s callers (in `main.selka` and in the test file) only read the result:
/// repaired. `passed_on`'s caller in `main.selka` and `returned_in_test`'s in the test file return it, which `from row` would refuse
/// there: the hint stays. A caller of `stored` (in the test file) and of `stored_in_main` stores it: neither. `shown` and
/// `shown_in_test` are named as a value in another module, which a `from` result cannot be: neither.
const public_returned_files = [_]File{
    .{ .path = "main.selka", .data = "import rows\n\n\nfunc passed_on(row: rows.Row) -> str:\n    return rows.passed_on(row)\n\n\n" ++
        "func keeps(row: rows.Row) -> int:\n    const held = rows.Holder(text=rows.stored_in_main(row))\n    return len(held.text)\n\n\n" ++
        "func main(out: Stream) -> int:\n    const row = rows.Row(name=\"a\", tags=[\"b\"])\n    const read = rows.shown\n" ++
        "    write(out, f\"{len(passed_on(row))} {len(read(row))} {keeps(row)}\\n\")\n    const tag = rows.tag_of(row) else:\n        return 0\n    return len(tag)\n" },
    .{ .path = "rows.selka", .data = "public record Row:\n    name: str\n    tags: str[]\n\n\npublic record Holder:\n    text: str\n\n\n" ++
        "public func tag_of(row: Row) -> str?:\n    if len(row.tags) == 0:\n        return None\n    return Some(copy(row.tags[0]))\n\n\n" ++
        "public func passed_on(row: Row) -> str:\n    return copy(row.name)\n\n\npublic func stored(row: Row) -> str:\n    return copy(row.name)\n\n\n" ++
        "public func stored_in_main(row: Row) -> str:\n    return copy(row.name)\n\n\npublic func returned_in_test(row: Row) -> str:\n    return copy(row.name)\n\n\n" ++
        "public func shown(row: Row) -> str:\n    return copy(row.name)\n\n\npublic func shown_in_test(row: Row) -> str:\n    return copy(row.name)\n" },
    .{ .path = "rows_test.selka", .data = "import rows\n\n\nfunc returned(row: rows.Row) -> str:\n    return rows.returned_in_test(row)\n\n\n" ++
        "public func test_tag_of() -> bool:\n    const row = rows.Row(name=\"a\", tags=[])\n    return rows.tag_of(row) is None\n\n\n" ++
        "public func test_stored() -> bool:\n    const row = rows.Row(name=\"a\", tags=[])\n    const held = rows.Holder(text=rows.stored(row))\n" ++
        "    return len(held.text) == 1 and len(returned(row)) == 1\n\n\n" ++
        "public func test_value() -> bool:\n    const row = rows.Row(name=\"a\", tags=[])\n    const read = rows.shown_in_test\n    return len(read(row)) == 1\n" },
};

/// Whether `stderr` holds the advice `code` ("every return of `name` copies a place of ...") for the function `name`.
fn hasReturnAdvice(stderr: []const u8, code: []const u8, name: []const u8) !bool {
    const needle = try std.fmt.allocPrint(testing.allocator, "[{s}]: every return of `{s}` copies a place of", .{ code, name });
    defer testing.allocator.free(needle);
    return contains(stderr, needle);
}

test "CLI fix also declares the result of a public function from the parameter in a project that is no package, cold and cached alike" {
    var cold = try Project.init(&public_returned_files);
    defer cold.deinit();
    var warm = try Project.init(&public_returned_files);
    defer warm.deinit();
    const unchecked = try warm.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer unchecked.deinit();
    const first = try warm.run("check", ".", &.{"--warnings"});
    defer first.deinit();
    const cached = try warm.run("check", ".", &.{"--warnings"});
    defer cached.deinit();
    try testing.expect(contains(unchecked.stderr, "warning[W_COPY_RETURNED]: every return of `tag_of` copies a place of `row`, and no caller keeps the result: " ++
        "declare it `from row` and return the places themselves; `tag_of` is public, so its signature changes"));
    // The warning stands for the hint at its place. A caller in another module or in the test file that returns the result
    // withholds it and the hint stays; one that stores it leaves both out, as for a private function; a function named as a value
    // in another module (`const read = rows.shown`) has neither.
    try testing.expect(!try hasReturnAdvice(unchecked.stderr, "W_COPY_MOVE", "tag_of"));
    for ([_][]const u8{ "passed_on", "returned_in_test" }) |name| {
        try testing.expect(!try hasReturnAdvice(unchecked.stderr, "W_COPY_RETURNED", name));
        try testing.expect(try hasReturnAdvice(unchecked.stderr, "W_COPY_MOVE", name));
    }
    for ([_][]const u8{ "stored", "stored_in_main", "shown", "shown_in_test" }) |name| {
        try testing.expect(!try hasReturnAdvice(unchecked.stderr, "W_COPY_RETURNED", name));
        try testing.expect(!try hasReturnAdvice(unchecked.stderr, "W_COPY_MOVE", name));
    }
    // Only the summary line's count of cached modules differs.
    const warning_end = std.mem.indexOf(u8, unchecked.stderr, "check: ok").?;
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], first.stderr[0..@min(warning_end, first.stderr.len)]);
    try testing.expectEqualStrings(unchecked.stderr[0..warning_end], cached.stderr[0..@min(warning_end, cached.stderr.len)]);
    try testing.expect(contains(cached.stderr, "check: ok (3 modules, 3 cached)"));
    // A check of the module alone does not hold every caller: the hint, no repair.
    const alone = try warm.run("check", "rows.selka", &.{"--warnings"});
    defer alone.deinit();
    try testing.expect(!contains(alone.stderr, "W_COPY_RETURNED"));
    try testing.expect(try hasReturnAdvice(alone.stderr, "W_COPY_MOVE", "tag_of"));
    const fixed_cold = try fixWithJobs(&cold, "1");
    defer fixed_cold.deinit();
    const fixed_warm = try fixWithJobs(&warm, "1");
    defer fixed_warm.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_cold.status);
    try testing.expectEqualStrings("fixed rows.selka: 2 edits (W_COPY_RETURNED)\nfix: 2 edits in 1 file over 1 round\n", fixed_cold.stdout);
    try testing.expectEqualStrings(fixed_cold.stdout, fixed_warm.stdout);
    const rows = try cold.read("rows.selka");
    defer testing.allocator.free(rows);
    try testing.expect(contains(rows, "public func tag_of(row: Row) -> str? from row:\n    if len(row.tags) == 0:\n        return None\n    return Some(row.tags[0])\n"));
    try testing.expect(contains(rows, "public func passed_on(row: Row) -> str:\n    return copy(row.name)\n"));
    try expectSameFile(&cold, &warm, "rows.selka");
    // No caller is edited.
    for ([_]usize{ 0, 2 }) |at| {
        const caller = try cold.read(public_returned_files[at].path);
        defer testing.allocator.free(caller);
        try testing.expectEqualStrings(public_returned_files[at].data, caller);
    }
    const clean = try cold.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "W_COPY_RETURNED"));
    try testing.expect(!try hasReturnAdvice(clean.stderr, "W_COPY_MOVE", "tag_of"));
    try testing.expect(try hasReturnAdvice(clean.stderr, "W_COPY_MOVE", "passed_on"));
    const again = try fixWithJobs(&cold, "1");
    defer again.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

/// One namespace, `numbers.selka` and `numbers/more.selka`: the shape of a package root, whose `public` `name_of` another project may call.
const package_returned_files = [_]File{
    .{ .path = "selka.json", .data = "{\"version\": 1}" },
    .{ .path = "numbers.selka", .data = "public record Row:\n    name: str\n\n\npublic func name_of(row: Row) -> str:\n    return copy(row.name)\n" },
    .{ .path = "numbers/more.selka", .data = "import numbers\n\n\npublic func size() -> int:\n    const row = numbers.Row(name=\"x\")\n    return len(numbers.name_of(row))\n" },
};

/// A second top-level name for `package_returned_files`: the project is then no package.
const second_namespace = "import numbers\n\n\npublic func other() -> int:\n    return len(numbers.Row(name=\"y\").name)\n";

/// Check `project` cold and cached (twice, the second replaying the first) and say whether each prints `W_COPY_RETURNED`: the
/// three print the same lines but for the summary's count of cached modules.
fn expectReturnedWarning(project: *const Project, printed: bool) !void {
    const cold = try project.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer cold.deinit();
    const first = try project.run("check", ".", &.{"--warnings"});
    defer first.deinit();
    const cached = try project.run("check", ".", &.{"--warnings"});
    defer cached.deinit();
    for ([_][]const u8{ cold.stderr, first.stderr, cached.stderr }) |stderr| {
        try testing.expectEqual(printed, contains(stderr, "W_COPY_RETURNED"));
    }
    const end = std.mem.indexOf(u8, cold.stderr, "check: ") orelse cold.stderr.len;
    try testing.expectEqualStrings(cold.stderr[0..end], first.stderr[0..@min(end, first.stderr.len)]);
    try testing.expectEqualStrings(cold.stderr[0..end], cached.stderr[0..@min(end, cached.stderr.len)]);
}

test "CLI check of a project that gains or loses a second namespace, or its interface_files, never replays the other answer for a public function" {
    var project = try Project.init(&package_returned_files);
    defer project.deinit();
    // One namespace (a package may hold it) keeps the public signature: the hint alone, and `fix` leaves it.
    try expectReturnedWarning(&project, false);
    const hint = try project.run("check", ".", &.{ "--warnings", "--no-cache" });
    defer hint.deinit();
    try testing.expect(try hasReturnAdvice(hint.stderr, "W_COPY_MOVE", "name_of"));
    const kept = try fixWithJobs(&project, "1");
    defer kept.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", kept.stdout);
    // A second namespace: the warning, in the very store the first answer filled.
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "other.selka", .data = second_namespace });
    try expectReturnedWarning(&project, true);
    // `interface_files` on: withheld again; off: back.
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\": 1, \"interface_files\": true}" });
    try expectReturnedWarning(&project, false);
    const publishing = try fixWithJobs(&project, "1");
    defer publishing.deinit();
    try testing.expect(!contains(publishing.stdout, "W_COPY_RETURNED"));
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = package_returned_files[0].data });
    try expectReturnedWarning(&project, true);
    // The second namespace gone: withheld once more, and the files are as they were written.
    try project.temp.dir.deleteFile(testing.io, "other.selka");
    try expectReturnedWarning(&project, false);
    const numbers = try project.read("numbers.selka");
    defer testing.allocator.free(numbers);
    try testing.expectEqualStrings(package_returned_files[1].data, numbers);
}

const clash_main = "import rows\n\n\nfunc main(out: Stream) -> int:\n    print(out, rows.total())\n    return 0\n";
const clash_records = "public record Row:\n    name: str\n    names: str[]\n\n\n";

/// A private `keys` that copies a place of its parameter, and a `gathered` that loops over its result and copies each element:
/// `W_COPY_RETURNED` would declare `keys` `from row`, and `W_NEEDLESS_COPY` has the loop take each element with `own`, which a
/// borrowed result refuses. The two are judged apart, so `from row` waits for a round of its own.
const clash_loop_files = [_]File{
    .{ .path = "main.selka", .data = clash_main },
    .{ .path = "rows.selka", .data = clash_records ++ "func keys(row: Row) -> str[]:\n    return copy(row.names)\n\n\n" ++
        "func gathered(row: Row) -> str[]:\n    mut out: str[] = [\"start\"]\n    for name in keys(row):\n        append(mut out, copy(name))\n    return out\n\n\n" ++
        "public func total() -> int:\n    const row = Row(name=\"a\", names=[\"x\", \"y\"])\n    return len(gathered(row)) + len(row.name)\n" },
};

/// The same `keys`, whose result `boxed` stores: `W_COPY_FOR_STORE` has `boxed` take `own items`, after which the caller's
/// `boxed(keys(row))` would need a copy of the result that `from row` would make a copy of the parameter's list.
const clash_store_files = [_]File{
    .{ .path = "main.selka", .data = clash_main },
    .{ .path = "rows.selka", .data = clash_records ++ "public record Box:\n    items: str[]\n\n\nfunc keys(row: Row) -> str[]:\n    return copy(row.names)\n\n\n" ++
        "func boxed(items: str[]) -> Box:\n    return Box(items=copy(items))\n\n\n" ++
        "public func total() -> int:\n    const row = Row(name=\"a\", names=[\"x\", \"y\"])\n    const box = boxed(keys(row))\n    return len(box.items) + len(row.name)\n" },
};

test "CLI fix leaves a result copying when another repair of the round makes its caller take it, cold and cached alike" {
    const expected = [_][]const u8{
        "fixed rows.selka: 2 edits (W_NEEDLESS_COPY)\nfix: 2 edits in 1 file over 1 round\n",
        "fixed rows.selka: 2 edits (W_COPY_FOR_STORE)\nfix: 2 edits in 1 file over 1 round\n",
    };
    const kept = [_][]const u8{
        "for name in own keys(row):\n        append(mut out, own name)\n",
        "func boxed(own items: str[]) -> Box:\n    return Box(items=own items)\n",
    };
    const shapes = [_][]const File{ &clash_loop_files, &clash_store_files };
    for (shapes, expected, kept) |files, summary, text| {
        var cold = try Project.init(files);
        defer cold.deinit();
        var warm = try Project.init(files);
        defer warm.deinit();
        // The check prints both repairs: the judge of `from row` sees the callers as they are written now.
        const before = try warm.run("check", ".", &.{ "--warnings", "--no-cache" });
        defer before.deinit();
        try testing.expect(contains(before.stderr, "warning[W_COPY_RETURNED]: every return of `keys` copies a place of `row`"));
        const primed = try warm.run("check", ".", &.{"--warnings"});
        defer primed.deinit();
        const fixed_cold = try fixWithJobs(&cold, "1");
        defer fixed_cold.deinit();
        const fixed_warm = try fixWithJobs(&warm, "1");
        defer fixed_warm.deinit();
        try testing.expectEqual(@as(u8, 0), fixed_cold.status);
        try testing.expectEqualStrings("", fixed_cold.stderr);
        // Only the other repair is written; `keys` keeps copying, and `from row` is judged again against the new caller.
        try testing.expectEqualStrings(summary, fixed_cold.stdout);
        try testing.expectEqualStrings(fixed_cold.stdout, fixed_warm.stdout);
        try expectSameFile(&cold, &warm, "rows.selka");
        const rows = try cold.read("rows.selka");
        defer testing.allocator.free(rows);
        try testing.expect(contains(rows, "func keys(row: Row) -> str[]:\n    return copy(row.names)\n"));
        try testing.expect(contains(rows, text));
        const total = rows[std.mem.indexOf(u8, rows, "public func total").?..];
        try testing.expect(!contains(total, "copy("));
        const clean = try cold.run("check", ".", &.{ "--warnings", "--no-cache" });
        defer clean.deinit();
        try testing.expectEqual(@as(u8, 0), clean.status);
        try testing.expect(!contains(clean.stderr, "W_COPY_RETURNED"));
        try testing.expect(!contains(clean.stderr, "E_SINGLE_OWNER_BORROW"));
        const again = try fixWithJobs(&cold, "1");
        defer again.deinit();
        try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
        const again_warm = try fixWithJobs(&warm, "1");
        defer again_warm.deinit();
        try testing.expectEqualStrings("fix: nothing to fix\n", again_warm.stdout);
    }
}

/// `returned_files` with an unused import in the program, which a round of its own deletes before `from` is judged.
const waiting_files = [_]File{
    .{ .path = "main.selka", .data = "import rows\nimport strings\n\n\nfunc main(out: Stream) -> int:\n    const row = rows.Row(name=\"a\", tags=[\"b\"])\n    write(out, f\"{rows.first_tag(row)} {rows.label(row)}\\n\")\n    return 0\n" },
    returned_files[1],
    returned_files[2],
};

test "CLI fix declares the result from the parameter in the round after the other repairs, which are counted in one closing line" {
    var project = try Project.init(&waiting_files);
    defer project.deinit();
    const fixed = try fixWithJobs(&project, "1");
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed main.selka: 1 edit (W_UNUSED_IMPORT)\nfixed rows.selka: 2 edits (W_COPY_RETURNED)\nfix: 3 edits in 2 files over 2 rounds\n", fixed.stdout);
    const again = try fixWithJobs(&project, "1");
    defer again.deinit();
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

/// `pooled_files` as one configured project: every entry is a module of it, so a round checks the directory once (FR23).
const project_files = pooled_files ++ [_]File{.{ .path = "selka.json", .data = "{\"version\": 1}\n" }};

/// `project_files` with a docstring example in `solo.selka`, which only a check of each entry compiles.
const example_files = [_]File{
    pooled_files[0],
    pooled_files[1],
    pooled_files[2],
    .{ .path = "solo.selka", .data = "public func twice(n: int) -> int:\n    \"\"\"Twice n.\n\n    >>> twice(2)\n    4\n    \"\"\"\n    return n * 2\n" },
    .{ .path = "selka.json", .data = "{\"version\": 1}\n" },
};

// spec-case: FIX-MIGRATION-1
test "CLI fix checks a directory that is one project once a round, where util.selka is shared by three entries, and makes the entries' edits" {
    var project = try Project.init(&project_files);
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{"--report"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    // One project check found the round's three repairs, one found nothing, and one checked the result: no entry
    // was checked on its own, where the run of `pooled_files` checks each of the four entries every round.
    try testing.expectEqualStrings("fixed util.selka: 2 edits (E_OWN_MARKER)\nfixed util_test.selka: 1 edit (E_OWN_MARKER)\nfix: 3 edits in 2 files over 1 round\n" ++
        "fix report: 1 round with edits, 3 directory checks, 0 entry checks, 0 example checks\n", fixed.stdout);
    const util = try project.read("util.selka");
    defer testing.allocator.free(util);
    try testing.expectEqualStrings("public func fill(mut rows: str[]):\n    const a = \"ab\" + \"cd\"\n    append(mut rows, own a)\n    const b = \"ef\" + \"gh\"\n    append(mut rows, own b)\n", util);
    // `--check` on the settled project is one clean project check and the final one.
    const again = try project.run("fix", ".", &.{ "--check", "--report" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\nfix report: 0 rounds with edits, 2 directory checks, 0 entry checks, 0 example checks\n", again.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix checks each entry of a project whose sources hold a docstring example, and makes the same edits" {
    var project = try Project.init(&example_files);
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{"--report"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed util.selka: 2 edits (E_OWN_MARKER)\nfixed util_test.selka: 1 edit (E_OWN_MARKER)\nfix: 3 edits in 2 files over 1 round\n"));
    try testing.expect(contains(fixed.stdout, " 0 directory checks, "));
    try testing.expect(!contains(fixed.stdout, " 0 entry checks, "));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix migrates lists.exchange callers to its own replacement: own at a last use, a copy otherwise" {
    // `lists.exchange(mut values, index, replacement)` copied a borrowed replacement; it
    // now takes `own replacement`. The original printed 16 before the change, and the
    // migrated program prints the same.
    const original = @embedFile("fixtures/fix-migration/lists-exchange-own.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_OWN_MARKER"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(@embedFile("fixtures/fix-migration/lists-exchange-own.expected.selka"), after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("16\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix rewrites integer bit operators to their prelude calls" {
    const original = @embedFile("fixtures/fix-migration/bit-operators.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_BIT_OPERATOR_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "bit_and(12, 10)"));
    try testing.expect(contains(after, "bit_or(1, bit_xor(2, bit_and(3, 1)))"));
    try testing.expect(contains(after, "bit_and(flags, 1) == 0"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes lists.contains for list membership with a call on one side, and the program prints the same answer (F-25)" {
    const original = @embedFile("fixtures/fix-migration/list-membership-calls.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_LIST_MEMBERSHIP_REMOVED"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "5 edits"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(@embedFile("fixtures/fix-migration/list-membership-calls.expected.selka"), after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stderr, "warning["));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqualStrings("1111\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix leaves list membership alone where both operands are calls or one passes a place mut (F-25)" {
    const original = @embedFile("fixtures/fix-migration/list-membership-uncertain.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, fixed.stderr, "error[E_LIST_MEMBERSHIP_REMOVED]"));
    try testing.expect(contains(fixed.stdout, "nothing to fix"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(original, after);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix rewrites removed option presence tests to the identity test" {
    const original = @embedFile("fixtures/fix-migration/option-presence.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_OPTION_COMPARISON_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "if value is None:"));
    try testing.expect(contains(after, "parse(\"x\") is not None"));
    try testing.expect(contains(after, "parse(\"2\") is None"));
    try testing.expect(contains(after, "parse(\"3\") is not None"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix splits receiver overlap into a preceding call without repeating effects" {
    const original = @embedFile("fixtures/fix-migration/receiver-overlap.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_FRONTEND_SYNTAX"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, after, "selected(mut items)"));
    try testing.expect(contains(after, " = selected(mut items)\n    items[mutation_result_"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{"--print-result"});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 12), ran.status);
    try testing.expectEqualStrings("12\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix reports what it cannot fix once and exits 1" {
    const library =
        \\
        \\
        \\public func grow(mut xs: int[]) -> Unit:
        \\    xs.append(missing)
        \\
    ;
    const first_test =
        \\import lib
        \\
        \\
        \\public func test_one() -> bool:
        \\    mut xs: int[] = []
        \\    lib.grow(xs)
        \\    return len(xs) == 1
        \\
    ;
    var project = try Project.init(&.{
        .{ .path = "lib.selka", .data = library },
        .{ .path = "first_test.selka", .data = first_test },
        .{ .path = "second_test.selka", .data = "import lib\n\n\npublic func test_two() -> bool:\n    mut xs: int[] = []\n    lib.grow(mut xs)\n    return True\n" },
    });
    defer project.deinit();
    const outcome = try project.run("fix", ".", &.{});
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.status);
    // The unknown name in the shared module is reported once, not per test file.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.stderr, "error[E_UNKNOWN_NAME]"));
    try testing.expect(contains(outcome.stdout, "fixed first_test.selka: 1 edit (E_MUTATION_MARKER)"));
    const fixed = try project.read("first_test.selka");
    defer testing.allocator.free(fixed);
    try testing.expect(contains(fixed, "lib.grow(mut xs)"));
    const json = try project.run("fix", ".", &.{"--diagnostics=json"});
    defer json.deinit();
    try testing.expect(contains(json.stderr, "\"version\":\"diagnostic-v1\""));
    const usage = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fix" } });
    defer testing.allocator.free(usage.stdout);
    defer testing.allocator.free(usage.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, usage.term);
    try testing.expect(contains(usage.stderr, "usage: selka fix"));
    try testing.expect(contains(usage.stderr, "<entry.selka|directory>...\n"));
}

// spec-case: CHECK-LIBRARY-2
test "CLI check checks a library module or a test file without main" {
    var project = try Project.init(&.{
        .{ .path = "lib.selka", .data = "\n\npublic func one() -> int:\n    return 1\n" },
        .{ .path = "broken.selka", .data = "\n\npublic func one() -> int:\n    return missing\n" },
        .{ .path = "plain_test.selka", .data = "func test_one() -> bool:\n    return True\n" },
    });
    defer project.deinit();
    const library = try project.run("check", "lib.selka", &.{});
    defer library.deinit();
    try testing.expectEqual(@as(u8, 0), library.status);
    try check_line.expectPassed(library.stderr);
    // A library's own error keeps its line, and the stub never shows up.
    const broken = try project.run("check", "broken.selka", &.{});
    defer broken.deinit();
    try testing.expectEqual(@as(u8, 1), broken.status);
    try testing.expect(contains(broken.stderr, "broken.selka:4:12: error[E_UNKNOWN_NAME]"));
    try testing.expect(!contains(broken.stderr, "E_MAIN"));
    const headerless_test = try project.run("check", "plain_test.selka", &.{});
    defer headerless_test.deinit();
    try testing.expectEqual(@as(u8, 0), headerless_test.status);
}

/// The pinned migration corpus: nine modules and tests of the value-semantics
/// Lox port (the copy the RC performance harness pins, 2026-09-29) with every
/// call-site `mut` marker stripped, as a program written before the markers
/// were required would read.
const lox_corpus = [_]File{
    .{ .path = "value.selka", .data = @embedFile("fixtures/fix-migration/lox/value.selka") },
    .{ .path = "table.selka", .data = @embedFile("fixtures/fix-migration/lox/table.selka") },
    .{ .path = "chunk.selka", .data = @embedFile("fixtures/fix-migration/lox/chunk.selka") },
    .{ .path = "object.selka", .data = @embedFile("fixtures/fix-migration/lox/object.selka") },
    .{ .path = "heap.selka", .data = @embedFile("fixtures/fix-migration/lox/heap.selka") },
    .{ .path = "lox_strings.selka", .data = @embedFile("fixtures/fix-migration/lox/lox_strings.selka") },
    .{ .path = "table_test.selka", .data = @embedFile("fixtures/fix-migration/lox/table_test.selka") },
    .{ .path = "heap_test.selka", .data = @embedFile("fixtures/fix-migration/lox/heap_test.selka") },
    .{ .path = "lox_strings_test.selka", .data = @embedFile("fixtures/fix-migration/lox/lox_strings_test.selka") },
};

/// How many of the corpus files `check` rejects.
fn rejectedFiles(project: *const Project) !usize {
    var rejected: usize = 0;
    for (lox_corpus) |file| {
        const outcome = try project.run("check", file.path, &.{});
        defer outcome.deinit();
        rejected += @intFromBool(outcome.status != 0);
    }
    return rejected;
}

// spec: FIX-MIGRATION-2
test "CLI fix migrates pinned pre-marker Lox syntax until every file checks" {
    var project = try Project.init(&lox_corpus);
    defer project.deinit();
    // Before: every file uses retired source syntax; writable calls also lack markers.
    try testing.expectEqual(@as(usize, 9), try rejectedFiles(&project));
    const migrated = try project.run("fix", ".", &.{});
    defer migrated.deinit();
    // Since 5C an optional Clock held by the runtime record is ordinary storage, so the refusals that used to remain
    // (`E_PROVIDER_STORAGE`) are gone and the migration reaches a clean check.
    try testing.expectEqual(@as(u8, 0), migrated.status);
    try testing.expectEqualStrings("", migrated.stderr);
    // The edits over 16 rounds (44 while a check stopped at the first ownership error of a program, F-RC-214) include the
    // ownership repairs heap.selka and lox_strings.selka reach once their stored
    // Clock no longer stops them (the 14 rounds before 5C ended at it), 47 E_PATTERN_QUALIFIED repairs, two
    // explicit ownership transfers in object.selka and one in table.selka (`t.entries = own entries`, reached
    // since `t.count = ...` in the loop over `t.entries` writes a field next to the one iterated and is accepted).
    // An entry file is not hidden by an importer,
    // so the byte-slice return in value.selka is repaired here instead of being
    // attributed to the importer and dropped, the byte-string method rows add
    // value.selka's two `E_METHOD_REMOVED` edits, and the retired list rows add
    // their own repairs across chunk, heap, object and table.
    // 534 since D4 (lane OC's H1): `mut entries = rt.strings.entries` in lox_strings.selka is only read, so it borrows and needs
    // no `copy(...)`.
    // 29 rounds since FR23, to the same 533 edits and the same tree: the directory is one project, so a round checks it once,
    // and that check stops at the first stage with an error in any file, where the 16 rounds of the entry-by-entry run went on
    // in every entry clear of it.
    // 537 since W13-S5: the two `encode()` calls of value.selka and heap_test.selka are refused, and each rewrite adds its
    // `strings` import, in the same rounds.
    try testing.expect(contains(migrated.stdout, "fix: 537 edits in 9 files over 29 rounds"));
    try testing.expect(contains(migrated.stdout, "fixed value.selka: 35 edits (E_MODULE_HEADER, E_BINDING_DECLARATION, E_FRONTEND_VARIANT, E_FRONTEND_SYNTAX, E_PATTERN_QUALIFIED, E_METHOD_REMOVED, E_SLICE_ESCAPES)"));
    try testing.expect(contains(migrated.stdout, "fixed heap.selka: 221 edits (E_MODULE_HEADER, E_BINDING_DECLARATION, E_FRONTEND_SYNTAX, E_METHOD_REMOVED, E_MUTATION_MARKER, E_PATTERN_QUALIFIED, E_NAMED_PATTERN, E_NAMED_FIELDS, E_OWN_MARKER, E_BORROW_UNDECLARED, E_SINGLE_OWNER_BORROW, E_SINGLE_OWNER_OVERLAP)"));
    // Every entry checks, with no source migration diagnostic left.
    const cases = [_]struct { path: []const u8, code: []const u8 }{
        .{ .path = "value.selka", .code = "" },
        .{ .path = "chunk.selka", .code = "" },
        .{ .path = "heap.selka", .code = "" },
        .{ .path = "heap_test.selka", .code = "" },
        .{ .path = "lox_strings.selka", .code = "" },
        .{ .path = "lox_strings_test.selka", .code = "" },
        .{ .path = "object.selka", .code = "" },
        .{ .path = "table.selka", .code = "" },
        .{ .path = "table_test.selka", .code = "" },
    };
    for (cases) |case| {
        const checked = try project.run("check", case.path, &.{"--diagnostics=json"});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, @intFromBool(case.code.len != 0)), checked.status);
        try testing.expectEqualStrings("", checked.stdout);
        if (case.code.len == 0) {
            try testing.expectEqualStrings("", checked.stderr);
        } else {
            const Diagnostic = struct { diagnostic: struct { code: []const u8 } };
            const parsed = try std.json.parseFromSlice(Diagnostic, testing.allocator, checked.stderr, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();
            try testing.expectEqualStrings(case.code, parsed.value.diagnostic.code);
        }
    }
    // A second pass makes no changes and reports nothing.
    const settled = try project.run("fix", ".", &.{"--check"});
    defer settled.deinit();
    try testing.expectEqual(@as(u8, 0), settled.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", settled.stdout);
    try testing.expectEqualStrings("", settled.stderr);
    const heap = try project.read("heap.selka");
    defer testing.allocator.free(heap);
    try testing.expect(contains(heap, "    mark_table(mut marker, rt.globals)\n"));
}

const abi_append_producer = "\npublic func change(mut items: int[]):\n    append(mut items, 9)\n\npublic func append_only(mut items: int[]):\n    append(mut items, 3)\n";
const abi_rebind_producer = "\npublic func change(mut items: int[]):\n    items = [7]\n    append(mut items, 8)\n\npublic func append_only(mut items: int[]):\n    append(mut items, 3)\n";
const abi_consumer =
    \\
    \\import lib
    \\func main() -> int:
    \\    mut first = [1]
    \\    mut first_saved = copy(first)
    \\    lib.change(mut first)
    \\    mut action = lib.change
    \\    mut second = [1]
    \\    mut second_saved = copy(second)
    \\    action(mut second)
    \\    mut third = [1]
    \\    mut third_saved = copy(third)
    \\    mut append = lib.append_only
    \\    append(mut third)
    \\    lib.append_only(mut third)
    \\    if first == second and first != [1] and first_saved == [1] and second_saved == [1] and third == [1, 3, 3] and third_saved == [1]:
    \\        return 1
    \\    else:
    \\        return 0
;

fn abiRun(project: *const Project) !void {
    const result = try project.run("run", "main.selka", &.{"--print-result"});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expectEqualStrings("1\n", result.stdout);
}

// spec-case: MUT-REBIND-CALLER-1
test "CLI warm imported direct and callback ABIs follow producer rebinding changes" {
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = abi_consumer }, .{ .path = "lib.selka", .data = abi_append_producer } });
    defer project.deinit();
    try abiRun(&project);
    try abiRun(&project);
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = abi_rebind_producer });
    try abiRun(&project);
    try abiRun(&project);
    const consumer = try project.read("main.selka");
    defer testing.allocator.free(consumer);
    try testing.expectEqualStrings(abi_consumer, consumer);
}

// spec: NEW-CORE-S5-ARENA-3
// spec-case: FIX-MIGRATION-1
test "CLI fix removes retired arena blocks, dedents their bodies and unwraps escapes" {
    const original = @embedFile("fixtures/fix-migration/arenas.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_ARENA_REMOVED"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(arenas_migrated, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try check_line.expectPassed(checked.stderr);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

/// `fixtures/fix-migration/arenas.selka` after `selka fix`.
const arenas_migrated =
    \\# Pre-S5 arena code: `selka fix` deletes every `with arena():` line, dedents
    \\# the block's body and rewrites each `name.escape(value)` to `value`.
    \\import strings
    \\
    \\record Reading:
    \\    sensor: int
    \\    samples: int[]
    \\
    \\
    \\func collect(sensors: int) -> Reading[]:
    \\    mut readings: Reading[] = []
    \\    for sensor in range(sensors):
    \\        # one region per sensor
    \\        mut samples: int[] = []
    \\        for index in range(3):
    \\            append(mut samples, sensor * 3 + index)
    \\
    \\        # kept: a copy survives the region
    \\        append(mut readings, Reading(sensor=sensor, samples=own samples))
    \\    return readings
    \\
    \\
    \\func loudest(readings: Reading[]) -> int:
    \\    mut best = 0
    \\# a comment at the left margin stays where it is
    \\    for reading in readings:
    \\        mut total = 0
    \\        for sample in reading.samples:
    \\            total = total + sample
    \\        if total > best:
    \\            best = total
    \\    return best
    \\
    \\
    \\func nested() -> int:
    \\    mut kept = "z"
    \\    mut joined = strings.join(["a", str(2)], "-")
    \\    kept = (joined + "!")
    \\    mut size = len(joined)
    \\    # after the inner block
    \\    return len(kept) + size
    \\
    \\
    \\func main() -> int:
    \\    mut readings = collect(4)
    \\    return len(readings) + loudest(readings) + nested()
    \\
;

// spec-case: NEW-CORE-S5-ARENA-3
test "F9 CLI fix repairs both sequential arena blocks reusing a name" {
    const original = "func main() -> int:\n    with arena() as a:\n        _ = len(a.escape([1]))\n    with arena() as a:\n        _ = len(a.escape([2]))\n    return 0\n";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(!contains(after, "with arena"));
    try testing.expect(!contains(after, "a.escape"));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, after, "len("));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try check_line.expectPassed(checked.stderr);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: NEW-CORE-S5-ARENA-3
test "F9 CLI fix still withholds nested arena name shadowing" {
    const original = "func main() -> int:\n    with arena() as a:\n        with arena() as a:\n            _ = len(a.escape([1]))\n    return 0\n";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(original, after);
    try testing.expect(contains(fixed.stderr, "E_ARENA_REMOVED"));
}

// spec-case: FIX-MIGRATION-1
// spec-case: D2-VIEW-STORAGE-1
test "D2 CLI fix materializes stored dictionary projections with contextual list snapshots" {
    const original = @embedFile("fixtures/fix-migration/dictionary-views.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_MODULE_HEADER"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "keys = list(dicts.keys(mapping))"));
    try testing.expect(contains(after, "values = list(dicts.values(mapping))"));
    try testing.expect(contains(after, "items = list(dicts.items(mapping))"));
    try testing.expect(contains(after, "nested = [list(dicts.values(mapping))]"));
    try testing.expect(contains(after, "interior = list(dicts.values(rows[0]))"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

fn storedViewCorpus(path: []const u8, text: []const u8) !void {
    var project = try Project.init(&.{.{ .path = path, .data = text }});
    defer project.deinit();
    const checked = try project.run("check", path, &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "E_VIEW_STORED"));
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects the former held receiver snapshot history and aggregate view corpora" {
    try storedViewCorpus("rc_dictionary_views.selka", @embedFile("fixtures/view-storage/rc_dictionary_views.selka"));
    try storedViewCorpus("rc_view_receivers.selka", @embedFile("fixtures/view-storage/rc_view_receivers.selka"));
    try storedViewCorpus("live_view_snapshots.selka", @embedFile("fixtures/view-storage/live_view_snapshots.selka"));
    try storedViewCorpus("rc_semantic_history.selka", @embedFile("fixtures/view-storage/rc_semantic_history.selka"));
}

/// The shapes from the EDA and Lox port migrations (2026-10-09) that `selka
/// fix` once broke: parse wrappers named for the builtin parser, and an
/// imported module whose union payloads, nested comprehensions, nested
/// conditionals and byte-literal conditionals carry overlapping repairs.
const port_defects = [_]File{
    .{ .path = "selka.json", .data = @embedFile("fixtures/fix-migration/port-defects/selka.json") },
    .{ .path = "main.selka", .data = @embedFile("fixtures/fix-migration/port-defects/main.selka") },
    .{ .path = "parsing.selka", .data = @embedFile("fixtures/fix-migration/port-defects/parsing.selka") },
    .{ .path = "shapes.selka", .data = @embedFile("fixtures/fix-migration/port-defects/shapes.selka") },
};

// spec: FIX-MIGRATION-OVERLAP-1
// spec-case: FRONTEND-NUMERIC-MIGRATION-3
// spec-case: FRONTEND-BYTES-PARENS-1
test "CLI fix migrates the port defect shapes without capture, overlapping edits or mangling" {
    var project = try Project.init(&port_defects);
    defer project.deinit();
    const migrated = try project.run("fix", ".", &.{});
    defer migrated.deinit();
    try testing.expectEqual(@as(u8, 1), migrated.status);
    try testing.expect(contains(migrated.stderr, "error[E_COMPREHENSION_REMOVED]"));
    try testing.expect(contains(migrated.stderr, "error[E_CONDITIONAL_EXPRESSION_REMOVED]"));
    // The certain ownership copy of a body that checks is made beside the withheld syntax repairs of other bodies (F-RC-214).
    try testing.expect(contains(migrated.stdout, "E_SINGLE_OWNER_BORROW"));
    const parsing = try project.read("parsing.selka");
    defer testing.allocator.free(parsing);
    // The wrapper `parse_int` is called bare in its own module, so it is renamed (W6, E_BUILTIN_FUNCTION_NAME) with its
    // qualified call in `main.selka`; a bare `parse_int(...)` is then always the builtin, so the numeric repairs write it.
    try testing.expect(contains(parsing, "public func parsing_parse_int(s: str) -> int?:\n    if len(s) == 0:\n        return None\n    return parse_int(s)\n"));
    const main_after = try project.read("main.selka");
    defer testing.allocator.free(main_after);
    try testing.expect(contains(main_after, "parsing.parsing_parse_int(\"12\")"));
    try testing.expect(contains(parsing, "import strings\n"));
    // The wrapper `parse_float` is not called bare, so it keeps its name and claims the parser's: the numeric repair once
    // wrote the `str` method `strings.strip(s).parse_float()`, which W13 removed, and now leaves the call for a hand edit.
    try testing.expect(contains(parsing, "    return float(strings.strip(s))\n"));
    try testing.expect(contains(migrated.stderr, "error[E_NUMERIC_PARSE]"));
    try testing.expect(contains(parsing, "    return parse_int(sign + digits)\n"));
    const shapes = try project.read("shapes.selka");
    defer testing.allocator.free(shapes);
    try testing.expect(contains(shapes, "public enum Tag:\n    items(value: Item[])\n    atom(value: bytes)\n    count(value: int)\n"));
    try testing.expect(contains(shapes, "    board\n    polygon(value: FixedArray[float, 2][])\n"));
    try testing.expect(contains(shapes, "for part in parts:"));
    try testing.expect(contains(shapes, "PartSpec(title=part.name, pads="));
    try testing.expect(contains(shapes, "for p in part.pins"));
    try testing.expect(contains(shapes, "    if c:\n        return 1\n    else:\n        if d:\n            return 2\n        else:\n            return 3\n"));
    try testing.expect(contains(shapes, "for x in xs:"));
    try testing.expect(contains(shapes, "if x > 0:"));
    // Preserve the historical before fixture. Repair only the migrated after
    // source, snapshotting the title and pins before constructing each pad list.
    const specs_start = std.mem.indexOf(u8, shapes, "public func specs(").?;
    const specs_end = std.mem.indexOfPos(u8, shapes, specs_start, "\n\npublic func pick(").?;
    const manual_specs =
        \\public func specs(parts: Part[]) -> PartSpec[]:
        \\    mut output: PartSpec[] = []
        \\    for part in parts:
        \\        const title = copy(part.name)
        \\        const pins = copy(part.pins)
        \\        mut pads: int[] = []
        \\        for p in pins:
        \\            pads.append(p + 1)
        \\        output.append(PartSpec(title=title, pads=pads))
        \\    return output
        \\
    ;
    const with_specs = try std.fmt.allocPrint(testing.allocator, "{s}{s}{s}", .{ shapes[0..specs_start], manual_specs, shapes[specs_end..] });
    defer testing.allocator.free(with_specs);
    // The later byte selection follows a computed prefix and needs a hand edit.
    const description_start = std.mem.indexOf(u8, with_specs, "public func describe(").?;
    const description_end = std.mem.indexOfPos(u8, with_specs, description_start, "\n\npublic func emit_shape(").?;
    const manual_description =
        \\public func describe(desc: bytes?, vias: bool) -> bytes:
        \\    const description: bytes
        \\    if desc is None:
        \\        description = b""
        \\    else:
        \\        description = copy(desc)
        \\    const allowance: bytes
        \\    if vias:
        \\        allowance = b"not_allowed"
        \\    else:
        \\        allowance = b"allowed"
        \\    return b"(descr " + description + b" " + allowance + b")"
        \\
    ;
    const manually_repaired = try std.fmt.allocPrint(testing.allocator, "{s}{s}{s}", .{ with_specs[0..description_start], manual_description, with_specs[description_end..] });
    defer testing.allocator.free(manually_repaired);
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "shapes.selka", .data = manually_repaired });
    // The claimed `parse_float` wrapper is a hand edit too: the `bytes` parser is a spelling no declaration captures,
    // and the `import bytes` it needs is the next `selka fix`'s repair (W13-S5: the `str` method that once served is gone).
    const hand_parsing = try std.mem.replaceOwned(u8, testing.allocator, parsing, "    return float(strings.strip(s))\n", "    return bytes.parse_float(strings.encode(strings.strip(s)))\n");
    defer testing.allocator.free(hand_parsing);
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "parsing.selka", .data = hand_parsing });
    // Finishing the withheld syntax repair leaves nothing the first run had not already repaired.
    const owned = try project.run("fix", ".", &.{});
    defer owned.deinit();
    try testing.expectEqual(@as(u8, 0), owned.status);
    try testing.expect(!contains(owned.stdout, "E_SINGLE_OWNER_BORROW"));
    const owned_shapes = try project.read("shapes.selka");
    defer testing.allocator.free(owned_shapes);
    try testing.expect(contains(owned_shapes, "emitted = copy(shape)"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    if (checked.status != 0) std.debug.print("port defect check: {s}{s}\n", .{ checked.stdout, checked.stderr });
    try testing.expectEqual(@as(u8, 0), checked.status);
    // The migrated program computes what the original did: no wrapper calls itself.
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 71), ran.status);
    const settled = try project.run("fix", ".", &.{"--check"});
    defer settled.deinit();
    try testing.expectEqual(@as(u8, 0), settled.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", settled.stdout);
}

// spec-case: FIX-MIGRATION-CAPTURE-1
test "CLI fix renames a float wrapper named like a builtin, so the removed helper inside it migrates without capture" {
    const original = @embedFile("fixtures/fix-migration/capture.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    // Before W6 the `f64_abs` inside the wrapper `abs` was left for a hand edit, since `abs(x)` there would have called the
    // wrapper itself. A bare `abs` is now always the builtin: the wrapper, which its module calls bare, is renamed
    // `main_abs` (E_BUILTIN_FUNCTION_NAME), and the `f64_abs` inside it then migrates to the builtin `abs(x)`.
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "E_REMOVED_SPELLING"));
    try testing.expect(contains(fixed.stdout, "E_BUILTIN_FUNCTION_NAME"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    return sqrt(x)\n"));
    try testing.expect(contains(after, "func main_abs(x: float) -> float:\n    return abs(x)\n"));
    try testing.expect(contains(after, "    return int(main_abs(-4.0) + root(9.0))\n"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 7), ran.status);
}

// spec-case: UNUSED-IMPORT-1
// spec-case: FIX-MIGRATION-1
test "qualified construction import stays used through cold warm checks and exact unused-import fix" {
    const used =
        \\import object
        \\import factory
        \\func main() -> int:
        \\    _ = object.Obj.empty
        \\    match factory.make():
        \\        case one(value=n):
        \\            return n
        \\        case empty:
        \\            return 0
        \\
    ;
    const original = "import spare\n" ++ used;
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = original },
        .{ .path = "object.selka", .data = "public enum Obj:\n    one(value: int)\n    empty\n" },
        .{ .path = "factory.selka", .data = "import object\npublic func make() -> object.Obj:\n    return object.Obj.one(value=1)\n" },
        .{ .path = "spare.selka", .data = "public func zero() -> int:\n    return 0\n" },
    });
    defer project.deinit();
    for (0..2) |_| {
        const checked = try project.run("check", "main.selka", &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
        try testing.expect(contains(checked.stderr, "import `spare`"));
        try testing.expect(!contains(checked.stderr, "import `object`"));
        try testing.expect(!contains(checked.stderr, "import `factory`"));
    }
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const actual = try project.read("main.selka");
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(used, actual);
    for (0..2) |_| {
        const checked = try project.run("check", "main.selka", &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
        try testing.expect(!contains(checked.stderr, "W_UNUSED_IMPORT"));
    }
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const final = try project.read("main.selka");
    defer testing.allocator.free(final);
    try testing.expectEqualStrings(used, final);
}

/// The `FIX-MIGRATION-1` contract for a retired method spelling: the pre-change
/// file reaches a clean check and a fixed point, and the migrated program prints
/// what the method spelling printed.
/// One generated migration: the retired spellings in `original` become calls in
/// `module`, its import lands in the same file, and the migrated program checks,
/// runs and prints what it printed before.
const Migration = struct {
    module: []const u8,
    retired: []const u8,
    edits: usize,
    prints: []const u8,
};

fn retiredMethodMigration(original: []const u8, migration: Migration) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "METHOD_REMOVED"));
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const migrated = try project.read("main.selka");
    defer testing.allocator.free(migrated);
    const import_line = try std.fmt.allocPrint(testing.allocator, "import {s}\n", .{migration.module});
    defer testing.allocator.free(import_line);
    try testing.expect(contains(migrated, import_line));
    const qualified = try std.fmt.allocPrint(testing.allocator, "{s}.", .{migration.module});
    defer testing.allocator.free(qualified);
    try testing.expect(contains(migrated, qualified));
    try testing.expect(!contains(migrated, migration.retired));
    try testing.expect(migration.edits != 0);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(migration.prints, ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix drops the type from qualified case patterns and keeps the program's result" {
    const original = @embedFile("fixtures/fix-migration/pattern-short-names.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_PATTERN_QUALIFIED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "        case left:\n            return 1\n"));
    try testing.expect(contains(after, "        case circle(radius=r):\n"));
    try testing.expect(contains(after, "        case Some(circle(radius=r)):\n"));
    try testing.expect(!contains(after, "case Side."));
    try testing.expect(!contains(after, "case Shape."));
    try testing.expect(!contains(after, "case Some(Shape."));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("1 12 7\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites a list's append and sort to the prelude writers" {
    const original = @embedFile("fixtures/fix-migration/list-writes.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "append(mut values, 3)"));
    try testing.expect(contains(after, "sort(mut values)"));
    try testing.expect(contains(after, "sort(mut descended, reverse=True)"));
    try testing.expect(contains(after, "sort(mut keyed, key=negate, reverse=False)"));
    try testing.expect(!contains(after, ".append("));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("1 5 9\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites a list's seven module words to their lists homes" {
    const original = @embedFile("fixtures/fix-migration/list-methods.selka");
    const wanted = @embedFile("fixtures/fix-migration/list-methods.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("None 1 3 4 6 0 0 0 1\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites a dictionary's nine method spellings to their dicts homes" {
    const original = @embedFile("fixtures/fix-migration/dict-methods.selka");
    const wanted = @embedFile("fixtures/fix-migration/dict-methods.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("1 7\n28 4 9 1\n2\n0\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites a set's nine method spellings to their sets homes, with the own marker" {
    const original = @embedFile("fixtures/fix-migration/set-methods.selka");
    const wanted = @embedFile("fixtures/fix-migration/set-methods.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("3 1 1\n2 False False False\n2 2\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites a stream's print and write methods to the stream-first functions" {
    const original = @embedFile("fixtures/fix-migration/stream-methods.selka");
    const wanted = @embedFile("fixtures/fix-migration/stream-methods.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("count: 3\n\n\ndone\n7\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes own for a copy of an owned local or own parameter at its last use, and keeps the copies a move would break" {
    const original = @embedFile("fixtures/fix-migration/own-last-use.selka");
    const wanted = @embedFile("fixtures/fix-migration/own-last-use.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const before_run = try project.run("run", "main.selka", &.{});
    defer before_run.deinit();
    try testing.expectEqual(@as(u8, 0), before_run.status);
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "W_NEEDLESS_COPY"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    // The moves hand over the bytes the copies made, so the program prints what it printed before.
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(before_run.stdout, ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes own for an owned name and a copy for a borrowed one at append and sets.add, and leaves the dicts calls alone" {
    const original = @embedFile("fixtures/fix-migration/append-own.selka");
    const wanted = @embedFile("fixtures/fix-migration/append-own.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_OWN_MARKER"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    // Marker repairs and explicit snapshots converge in two rounds (eleven while a check stopped at a body's first
    // ownership error). A const alias receives its copy at the initializer before its own transfer.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "over 2 rounds"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    // The migrated program prints what the copies and the moves leave it to print.
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("12\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix renames a type declared under a builtin type's name, and the qualified references to it in the modules that import it" {
    const root = "fixtures/fix-migration/builtin-type-name/";
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") },
        .{ .path = "emit.selka", .data = @embedFile(root ++ "emit.selka") },
        .{ .path = "kicad/shape.selka", .data = @embedFile(root ++ "kicad/shape.selka") },
    });
    defer project.deinit();
    // The declaration is refused, and nothing is written by a preview.
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_BUILTIN_TYPE_NAME"));
    // The program ran before the change, printing `noted` and `2 9 x` and exiting with the status of `describe`; the bare `Unit` in
    // `note` is the builtin and stays as written.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed kicad/shape.selka: 1 edit (E_BUILTIN_TYPE_NAME)"));
    try testing.expect(contains(fixed.stdout, "fixed emit.selka: 3 edits (E_BUILTIN_TYPE_NAME)"));
    try expectFile(&project, "main.selka", @embedFile(root ++ "main.expected.selka"));
    try expectFile(&project, "emit.selka", @embedFile(root ++ "emit.expected.selka"));
    try expectFile(&project, "kicad/shape.selka", @embedFile(root ++ "kicad/shape.expected.selka"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 1), ran.status);
    try testing.expectEqualStrings("noted\n2 9 x\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix renames the uses inside a module that builds its own type under a builtin name, which never checked" {
    const root = "fixtures/fix-migration/builtin-type-name-uses/";
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") },
        .{ .path = "shape.selka", .data = @embedFile(root ++ "shape.selka") },
    });
    defer project.deinit();
    // Before the repair the module does not check: `Unit(number=...)` named the builtin.
    const before = try project.run("check", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 1), before.status);
    try testing.expect(contains(before.stderr, "E_BUILTIN_TYPE_NAME"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed shape.selka: 6 edits (E_BUILTIN_TYPE_NAME)"));
    try expectFile(&project, "shape.selka", @embedFile(root ++ "shape.expected.selka"));
    try expectFile(&project, "main.selka", @embedFile(root ++ "main.expected.selka"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("3 1 True\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes old(copy(x)) for each old(...) of a managed place and leaves scalar and written captures alone (W4)" {
    const root = "fixtures/fix-migration/old-copy/";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") }});
    defer project.deinit();
    const before = try project.run("check", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 1), before.status);
    try testing.expectEqual(@as(usize, 7), std.mem.count(u8, before.stderr, "error[E_CONTRACT_OLD_COPY]"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 7 edits (E_CONTRACT_OLD_COPY)"));
    try expectFile(&project, "main.selka", @embedFile(root ++ "main.expected.selka"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    // The program prints what it printed before the refusal: the written copy is the copy the capture made.
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("5 2 hi! True 2 1 5\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix repairs generic bodies refused at their declaration with from on the result and copy on a stored value (W3)" {
    const root = "fixtures/fix-migration/generic-declaration/";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") }});
    defer project.deinit();
    // The helpers were written for `int` callers; each body is refused at its declaration for a managed type argument.
    const before = try project.run("check", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 1), before.status);
    try testing.expectEqual(@as(usize, 4), std.mem.count(u8, before.stderr, "error[E_BORROW_UNDECLARED]: the body of"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, before.stderr, "error[E_SINGLE_OWNER_BORROW]: the body of `keep`"));
    try testing.expect(contains(before.stderr, "the body of `right_of` is refused when `B` is a text, a record with a managed field or a list;"));
    // `forward` returns `identity(value)`: it is refused only once `identity` declares its borrowed result, a second round.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 7 edits (E_BORROW_UNDECLARED, E_SINGLE_OWNER_BORROW)"));
    try testing.expect(contains(fixed.stdout, "over 2 rounds"));
    try expectFile(&project, "main.selka", @embedFile(root ++ "main.expected.selka"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("3 7 1 9 2\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes and removes own and writes copy in generic bodies refused at their declaration, every kind alike (FR88)" {
    const root = "fixtures/fix-migration/generic-own-marker/";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") }});
    defer project.deinit();
    const before = try project.run("check", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 1), before.status);
    try testing.expectEqual(@as(usize, 5), std.mem.count(u8, before.stderr, "error[E_OWN_MARKER]: the body of"));
    try testing.expect(contains(before.stderr, "error[E_SINGLE_OWNER_BORROW]: the body of `enclose` is refused when `K` is any kind of type"));
    try testing.expect(contains(before.stderr, "write `own fresh` to give it"));
    // Three functions' first faults are one round; `chain`'s second and third faults are each reported once the one
    // before is repaired, a round each: a template is refused once, at its declaration, with its first fault as the note.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 9 edits (E_OWN_MARKER, E_SINGLE_OWNER_BORROW)"));
    try testing.expect(contains(fixed.stdout, "over 3 rounds"));
    try expectFile(&project, "main.selka", @embedFile(root ++ "main.expected.selka"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("3 c 4 5 p 6 7\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix renames module functions with prelude names that their modules call bare, and qualifies a re-export's bare uses" {
    const root = "fixtures/fix-migration/builtin-function-name/";
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = @embedFile(root ++ "main.selka") },
        .{ .path = "shapes.selka", .data = @embedFile(root ++ "shapes.selka") },
        .{ .path = "collide.selka", .data = @embedFile(root ++ "collide.selka") },
        .{ .path = "report.selka", .data = @embedFile(root ++ "report.selka") },
        .{ .path = "helpers.selka", .data = @embedFile(root ++ "helpers.selka") },
        .{ .path = "rounding.selka", .data = @embedFile(root ++ "rounding.selka") },
        .{ .path = "measure.selka", .data = @embedFile(root ++ "measure.selka") },
    });
    defer project.deinit();
    // Before W6 and N4 this program printed `30 17 100 6 100` and `4.0 9.0 9.0`: each bare `sum`, `abs`, `len`, `max`, `sqrt`,
    // `floor`, `ceil` and `trunc` called the module's own (or the re-exported) function.
    const before = try project.run("check", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 1), before.status);
    try testing.expect(contains(before.stderr, "E_BUILTIN_FUNCTION_NAME"));
    // `helpers.max` is never called bare in its own module, so it is not refused.
    try testing.expect(!contains(before.stderr, "helpers.selka:"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed shapes.selka: 4 edits (E_BUILTIN_FUNCTION_NAME)"));
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 1 edit (E_BUILTIN_FUNCTION_NAME)"));
    try testing.expect(contains(fixed.stdout, "fixed collide.selka: 2 edits (E_BUILTIN_FUNCTION_NAME)"));
    try testing.expect(contains(fixed.stdout, "fixed report.selka: 1 edit (E_BUILTIN_FUNCTION_NAME)"));
    // N4: `sqrt`, `floor`, `ceil` and `trunc` are prelude names too.
    try testing.expect(contains(fixed.stdout, "fixed rounding.selka: 6 edits (E_BUILTIN_FUNCTION_NAME)"));
    try testing.expect(contains(fixed.stdout, "fixed measure.selka: 1 edit (E_BUILTIN_FUNCTION_NAME)"));
    try expectFile(&project, "main.selka", @embedFile(root ++ "main.expected.selka"));
    try expectFile(&project, "shapes.selka", @embedFile(root ++ "shapes.expected.selka"));
    try expectFile(&project, "collide.selka", @embedFile(root ++ "collide.expected.selka"));
    try expectFile(&project, "report.selka", @embedFile(root ++ "report.expected.selka"));
    try expectFile(&project, "helpers.selka", @embedFile(root ++ "helpers.selka"));
    try expectFile(&project, "rounding.selka", @embedFile(root ++ "rounding.expected.selka"));
    try expectFile(&project, "measure.selka", @embedFile(root ++ "measure.expected.selka"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("30 17 100 6 100\n4.0 9.0 9.0\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix drops a field default that builds a record without its required field, and the program prints what it printed" {
    const original = @embedFile("fixtures/fix-migration/unbuildable-default.selka");
    const wanted = @embedFile("fixtures/fix-migration/unbuildable-default.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    // The default is refused at the declaration, with the one repair: delete it.
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_INCOMPLETE_CONSTRUCTION"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 2 edits (E_INCOMPLETE_CONSTRUCTION)"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    // The migrated program prints what the original printed before the refusal existed: 3 + 1 + 3.
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("7\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix gives every http.Error match the arms of the cases it split into, copied from the case it used to be" {
    const original = @embedFile("fixtures/fix-migration/http-error-kinds.selka");
    const wanted = @embedFile("fixtures/fix-migration/http-error-kinds.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_INCOMPLETE_MATCH"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    // The limit refusals and the other version are answered by the arms they were answered by before the split.
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("0 1 2 3 2 2\nmalformed: header section is too large\nunsupported: only HTTP/1.0 and HTTP/1.1 are supported\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix gives a stored resource parameter and its call sites the own mode" {
    const original = @embedFile("fixtures/fix-migration/own-resource.selka");
    const wanted = @embedFile("fixtures/fix-migration/own-resource.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_SINGLE_OWNER_BORROW"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    // The repair pair is certain: the declaration takes its value and every
    // call site gives it away, so the result checks clean.
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes the copy that each hidden view copy makes, and the program prints the same line" {
    const original = @embedFile("fixtures/fix-migration/hidden-view-copies.selka");
    const wanted = @embedFile("fixtures/fix-migration/hidden-view-copies.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    // The stream refusal answers first in its body (one diagnostic per body), so the
    // repair it hides runs in a later round; the fixed run names it.
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    // Every repair writes `copy(...)` around one view, and nothing else changes:
    // the fixed program checks clean and prints the value the copy-free one did.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "E_SLICE_ESCAPES"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("38\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix gives a plain resource parameter and its call site the own mode" {
    const original = @embedFile("fixtures/fix-migration/own-plain-resource.selka");
    const wanted = @embedFile("fixtures/fix-migration/own-plain-resource.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_OWN_PARAMETER"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    // The declaration and call transfer the resource, as do the constructor,
    // local binding and discard. Their repairs converge in two rounds (five while a check stopped at a body's first error).
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "over 2 rounds"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix marks a bare argument for an implicit Some and the marked call converges" {
    const original = @embedFile("fixtures/fix-migration/own-implicit-some.selka");
    const wanted = @embedFile("fixtures/fix-migration/own-implicit-some.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 1 edit (E_OWN_MARKER)"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    // The one repair inserts own before the name; the call then checks and nothing is left.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 1 edit (E_OWN_MARKER)"));
    try testing.expect(contains(fixed.stdout, "over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expect(contains(again.stdout, "nothing to fix"));
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites retired text methods to their function homes" {
    try retiredMethodMigration(
        @embedFile("fixtures/fix-migration/string-methods.selka"),
        .{ .module = "strings", .retired = ".upper()", .edits = 9, .prints = "11 28 0\n" },
    );
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites retired text search methods to the option convention" {
    try retiredMethodMigration(
        @embedFile("fixtures/fix-migration/text-search.selka"),
        .{ .module = "strings", .retired = "text.find(", .edits = 8, .prints = "101 101010 13\n" },
    );
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites retired byte-string methods to their function homes" {
    try retiredMethodMigration(
        @embedFile("fixtures/fix-migration/bytes-methods.selka"),
        .{ .module = "bytes", .retired = "b\"-\".join(", .edits = 10, .prints = "14 11\n" },
    );
}

// spec-case: FIX-MIGRATION-1
test "CLI fix gives a view-returning function used as a value a copying wrapper beside it" {
    const original = @embedFile("fixtures/fix-migration/view-function-value.selka");
    const wanted = @embedFile("fixtures/fix-migration/view-function-value.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    // The stream refusal answers first in its body (one diagnostic per body), so the
    // repair it hides runs in a later round; the fixed run names it.
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "E_VIEW_FUNCTION_VALUE"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    // The migrated program checks clean, runs with the same output as the original
    // would had it been accepted (the copy holds the same four octets), and has no
    // repair left to make.
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("4\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix puts an imported view function's copying wrapper at the end of the importing module" {
    const main_text =
        \\import texts
        \\func apply(callback: func(str) -> str, text: str) -> int:
        \\    return len(callback(text))
        \\func main(out: Stream) -> int:
        \\    print(out, apply(texts.head, "abcdefgh"))
        \\    return 0
        \\
    ;
    // This case isolates the caller adapter: the imported borrow contract is
    // already declared, so fixing the call must leave its module unchanged.
    const texts_text = "public func head(text: str) -> str from text:\n    return text[0:4]\n";
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = main_text }, .{ .path = "texts.selka", .data = texts_text } });
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "print(out, apply(head_copy, \"abcdefgh\"))"));
    try testing.expect(contains(after, "\n\nfunc head_copy(text: str) -> str:\n    return copy(texts.head(text))\n"));
    const unchanged = try project.read("texts.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(texts_text, unchanged);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("4\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix copies a strip result bound before its text is replaced" {
    const original = @embedFile("fixtures/fix-migration/strip-view-binding.selka");
    const wanted = @embedFile("fixtures/fix-migration/strip-view-binding.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    // The stream refusal answers first in its body (one diagnostic per body), so the
    // repair it hides runs in a later round; the fixed run names it.
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "E_SINGLE_OWNER_OVERLAP"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("abc\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes the copy a text or bytes slice given to an own parameter needs, and the program prints the same line (D8)" {
    const original = @embedFile("fixtures/fix-migration/text-slice-own.selka");
    const expected = @embedFile("fixtures/fix-migration/text-slice-own.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expectEqual(@as(usize, 5), std.mem.count(u8, refused.stderr, "error[E_SLICE_ESCAPES]"));
    try testing.expectEqual(@as(usize, 5), std.mem.count(u8, refused.stderr, "note: ownership rule W4"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 10 edits in 1 file over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqualStrings("2 2 21 4 2\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes the copy at the binding a write through a borrowing mut local needs, once, and settles (D4)" {
    const original = @embedFile("fixtures/fix-migration/written-through.selka");
    const expected = @embedFile("fixtures/fix-migration/written-through.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    // Three writes, each refused at the write; each repair edits its binding (two edits: `copy(` and `)`).
    try testing.expect(contains(preview.stdout, "6 edits (E_SINGLE_OWNER_BORROW)"));
    const checked_before = try project.run("check", "main.selka", &.{});
    defer checked_before.deinit();
    try testing.expect(contains(checked_before.stderr, "main.selka:15:5: error[E_SINGLE_OWNER_BORROW]: `counts` is lent by the plain parameter `shelf`, and a write through `counts` needs its own value"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqualStrings("4 2 9 1 1\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes the copy a stored char_slice needs and leaves the program's result" {
    const original = @embedFile("fixtures/fix-migration/char-slice-copies.selka");
    const expected = @embedFile("fixtures/fix-migration/char-slice-copies.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    // The function's undeclared return is repaired before its stored slices.
    try testing.expect(contains(preview.stdout, "E_BORROW_UNDECLARED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
// spec-case: METHOD-REMOVED-1
test "CLI fix rewrites a byte buffer's write spellings to their buffers homes" {
    const original = @embedFile("fixtures/fix-migration/buffer-methods.selka");
    const wanted = @embedFile("fixtures/fix-migration/buffer-methods.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_METHOD_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("8 True\n0\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix takes an element binding to a const borrow or its write-back, and copies a return, to a clean check" {
    const original = @embedFile("fixtures/fix-migration/borrow-repairs.selka");
    const wanted = @embedFile("fixtures/fix-migration/borrow-repairs.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_SINGLE_OWNER_BORROW"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    // The program's result is the value the original's element reads and writes give: 6 + 2 * 10.
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 26), ran.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix takes accessor results that now borrow, moved payloads and stored results, to a clean check with the same output" {
    const original = @embedFile("fixtures/fix-migration/accessor-borrows.selka");
    const wanted = @embedFile("fixtures/fix-migration/accessor-borrows.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    // The returned accessor borrows the document, so its declaration is fixed
    // before the moved payload and stored result are visited in later rounds.
    try testing.expect(contains(preview.stdout, "E_BORROW_UNDECLARED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("widget 2 widget\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// FIX-MIGRATION-1: accepted fused retained ranges migrate to ordinary slices.
test "CLI fix retires retained views including generic numeric range fusion" {
    const original = @embedFile("fixtures/fix-migration/retained-views.selka");
    const wanted = @embedFile("fixtures/fix-migration/retained-views.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_BORROW_VIEWS_REMOVED"));
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("42\n42\n42\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// FIX-MIGRATION-1: borrowed-result declarations migrate through the public CLI.
test "O3 borrowed signatures fix imported declarations including wrappers slices mut and generic instances" {
    const original = @embedFile("fixtures/fix-migration/borrowed_signatures/accessors.selka");
    const wanted = @embedFile("fixtures/fix-migration/borrowed_signatures/accessors.expected.selka");
    const entry = @embedFile("fixtures/fix-migration/borrowed_signatures/main.selka");
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = entry },
        .{ .path = "accessors.selka", .data = original },
    });
    defer project.deinit();
    const diagnostic = try project.run("check", "main.selka", &.{ "--no-cache", "--diagnostics=json" });
    defer diagnostic.deinit();
    try testing.expectEqual(@as(u8, 1), diagnostic.status);
    try testing.expect(contains(diagnostic.stderr, "E_BORROW_UNDECLARED"));
    try testing.expect(contains(diagnostic.stderr, "\"path\":\"accessors.selka\""));
    try testing.expect(contains(diagnostic.stderr, "\"fix\":{\"edits\":"));
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix accessors.selka:"));
    const untouched = try project.read("accessors.selka");
    defer testing.allocator.free(untouched);
    try testing.expectEqualStrings(original, untouched);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "E_BORROW_UNDECLARED"));
    const after = try project.read("accessors.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const main_after = try project.read("main.selka");
    defer testing.allocator.free(main_after);
    try testing.expectEqualStrings(entry, main_after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 42), ran.status);
    try testing.expectEqualStrings("", ran.stderr);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

test "O3 borrowed signatures fix extends one clause in parameter order" {
    const original =
        // migrate-embedded: skip intentional O3 missing borrow source repair input
        \\func selected(left: str[], right: str[], use_left: bool) -> str[] from right:
        \\    if use_left:
        \\        return left
        \\    return right
        \\
        \\func main() -> int:
        \\    const value = selected(["left"], ["right"], True)
        \\    return len(value)
        \\
    ;
    const wanted =
        \\func selected(left: str[], right: str[], use_left: bool) -> str[] from left, right:
        \\    if use_left:
        \\        return left
        \\    return right
        \\
        \\func main() -> int:
        \\    const value = selected(["left"], ["right"], True)
        \\    return len(value)
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "E_BORROW_UNDECLARED"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

test "O3 borrowed signatures mixed return repair copies borrowed paths and removes the clause" {
    const original =
        // migrate-embedded: skip intentional O3 mixed return repair input
        \\func pick(values: str[], make_new: bool) -> str[] from values:
        \\    if make_new:
        \\        return ["new"]
        \\    return values
        \\
        \\func main() -> int:
        \\    return len(pick(["old"], False))
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const diagnostic = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer diagnostic.deinit();
    try testing.expectEqual(@as(u8, 1), diagnostic.status);
    try testing.expect(contains(diagnostic.stderr, "E_BORROW_MIXED"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "func pick(values: str[], make_new: bool) -> str[]:"));
    try testing.expect(contains(after, "return copy(values)"));
    try testing.expect(!contains(after, " from values"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

const OwnedMigration = struct {
    original: []const u8,
    wanted: []const u8,
    printed: []const u8,
    first_rule: []const u8,
    /// The migration's repairs include a warning's, which a file run applies only with `--warnings`.
    warnings: bool = false,
};

/// The public migration reports a certain marker repair, writes its exact golden,
/// preserves the result, and leaves both preview and repeated application stable.
fn ownedMoveMigration(backing: std.mem.Allocator, migration: OwnedMigration) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = migration.original }});
    defer project.deinit();
    const apply: []const []const u8 = if (migration.warnings) &.{"--warnings"} else &.{};
    const list: []const []const u8 = if (migration.warnings) &.{ "--check", "--warnings" } else &.{"--check"};
    const diagnostic = try project.run("check", "main.selka", &.{ "--no-cache", "--diagnostics=json" });
    defer diagnostic.deinit();
    try testing.expectEqual(@as(u8, 1), diagnostic.status);
    try testing.expect(contains(diagnostic.stderr, "\"code\":\"E_OWN_MARKER\""));
    const rule = try std.fmt.allocPrint(backing, "\"rule\":\"{s}\"", .{migration.first_rule});
    defer backing.free(rule);
    try testing.expect(contains(diagnostic.stderr, rule));
    try testing.expect(contains(diagnostic.stderr, "\"fix\":{\"edits\":"));
    const preview = try project.run("fix", "main.selka", list);
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_OWN_MARKER"));
    const untouched = try project.read("main.selka");
    defer backing.free(untouched);
    try testing.expectEqualStrings(migration.original, untouched);
    const fixed = try project.run("fix", "main.selka", apply);
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |err| {
        std.debug.print("O4 marker migration: {s}\n{s}\n", .{ fixed.stdout, fixed.stderr });
        return err;
    };
    try testing.expect(contains(fixed.stdout, "E_OWN_MARKER"));
    const after = try project.read("main.selka");
    defer backing.free(after);
    try testing.expectEqualStrings(migration.wanted, after);
    for ([_][]const []const u8{ &.{"--no-cache"}, &.{} }) |args| {
        const checked = try project.run("check", "main.selka", args);
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
        try testing.expect(!contains(checked.stderr, "E_OWN_MARKER"));
    }
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(migration.printed, ran.stdout);
    const preview_again = try project.run("fix", "main.selka", list);
    defer preview_again.deinit();
    try testing.expectEqual(@as(u8, 0), preview_again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", preview_again.stdout);
    const fixed_again = try project.run("fix", "main.selka", apply);
    defer fixed_again.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", fixed_again.stdout);
    const stable = try project.read("main.selka");
    defer backing.free(stable);
    try testing.expectEqualStrings(migration.wanted, stable);
}

// spec-case: FIX-MIGRATION-1
test "O4 owned moves fix bindings stores constructors and calls without changing values" {
    try ownedMoveMigration(testing.allocator, .{
        .original = @embedFile("fixtures/fix-migration/owned_moves/moves.selka"),
        .wanted = @embedFile("fixtures/fix-migration/owned_moves/moves.expected.selka"),
        .printed = "55\n",
        .first_rule = "B2",
    });
}

// spec-case: FIX-MIGRATION-1
test "O4 owned moves fix const aliases at their initializers before later transfers" {
    try ownedMoveMigration(testing.allocator, .{
        .original = @embedFile("fixtures/fix-migration/owned_moves/aliases.selka"),
        .wanted = @embedFile("fixtures/fix-migration/owned_moves/aliases.expected.selka"),
        .printed = "152\n",
        .first_rule = "B9",
    });
}

// spec-case: FIX-MIGRATION-1
test "O4 owned moves fix redundant markers but preserve a field return carrier move" {
    try ownedMoveMigration(testing.allocator, .{
        .original = @embedFile("fixtures/fix-migration/owned_moves/redundant.selka"),
        .wanted = @embedFile("fixtures/fix-migration/owned_moves/redundant.expected.selka"),
        .printed = "41\n",
        .first_rule = "B2",
        .warnings = true,
    });
}

const FxDiagnostic = struct {
    code: []const u8,
    rule: ?[]const u8 = null,
    message: []const u8 = "",
    at: ?[]const u8 = null,
    related: bool = false,
    mentions: []const []const u8 = &.{},
};

fn fxRefusal(text: []const u8, expected: FxDiagnostic) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var project = try Project.init(&.{.{ .path = "main.selka", .data = text }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    var lines = std.mem.splitScalar(u8, checked.stderr, '\n');
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), lines.next().?, .{});
    const diagnostic = parsed.value.object.get("diagnostic").?.object;
    try testing.expectEqualStrings(expected.code, diagnostic.get("code").?.string);
    if (expected.rule) |rule| try testing.expectEqualStrings(rule, diagnostic.get("rule").?.string);
    try testing.expect(contains(diagnostic.get("message").?.string, expected.message));
    if (expected.at) |at| {
        const bytes = diagnostic.get("location").?.object.get("bytes").?.object;
        const start: usize = @intCast(bytes.get("start").?.integer);
        const end: usize = @intCast(bytes.get("end").?.integer);
        try testing.expectEqualStrings(at, text[start..end]);
    }
    if (expected.related) try testing.expect(diagnostic.get("notes").?.array.items.len != 0);
    for (expected.mentions) |part| try testing.expect(contains(diagnostic.get("message").?.string, part));
}

fn fxRepair(original: []const u8, wanted: []const u8) !void {
    try fxRepairWith(original, wanted, false);
}

/// `fxRepair` for a source whose repairs include a warning's (`W_NEEDLESS_COPY`): a file run applies those only with `--warnings`.
fn fxRepairWarnings(original: []const u8, wanted: []const u8) !void {
    try fxRepairWith(original, wanted, true);
}

fn fxRepairWith(original: []const u8, wanted: []const u8, warnings: bool) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", if (warnings) &.{"--warnings"} else &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const stable = try project.run("fix", "main.selka", if (warnings) &.{ "--check", "--warnings" } else &.{"--check"});
    defer stable.deinit();
    try testing.expectEqual(@as(u8, 0), stable.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", stable.stdout);
}

// spec-case: FIX-MIGRATION-1
test "F2 contextual own arithmetic is untouched by fix" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("func main() -> int:\n" ++
        "    const own = 10\n" ++
        "    const y = own - 1\n" ++
        "    return y\n", "func main() -> int:\n" ++
        "    const own = 10\n" ++
        "    const y = own - 1\n" ++
        "    return y\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("func main() -> int:\n" ++
        "    const own = 10\n" ++
        "    return 3 + own - 1\n", "func main() -> int:\n" ++
        "    const own = 10\n" ++
        "    return 3 + own - 1\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("func main() -> int:\n" ++
        "    const own = 10\n" ++
        "    if own - 2 == 8:\n" ++
        "        return 9\n" ++
        "    return 0\n", "func main() -> int:\n" ++
        "    const own = 10\n" ++
        "    if own - 2 == 8:\n" ++
        "        return 9\n" ++
        "    return 0\n");
}

// spec-case: FIX-MIGRATION-1
test "F5 bare fail transfers while redundant fail own repairs to a fixed point" {
    try ownedMoveMigration(testing.allocator, .{
        .original = @embedFile("fixtures/fix-migration/fail-name.selka"),
        .wanted = @embedFile("fixtures/fix-migration/fail-name.expected.selka"),
        .printed = "7\n",
        .first_rule = "B2",
    });
}

// spec-case: MUT-EXCLUSIVE-3
test "F6 M5 identifies both arguments and gives a mutable writeback instead of a bare copy" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("func nested(mut xs: int[][], mut ys: int[]):\n" ++
        "    append(mut xs, [5])\n" ++
        "    append(mut ys, 9)\n" ++
        "func main() -> int:\n" ++
        "    mut a = [[1, 2], [3]]\n" ++
        "    nested(mut a, mut a[0])\n" ++
        "    return 0\n", .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = "M5", .related = true, .message = "a[0] = own part", .mentions = &.{ "mut part = copy(a[0])", "mut part" } });
}
test "F6 move repair copies later-used names and carriers but transfers last uses" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    const value = [1]\n" ++
        "    const count = my_take(value)\n" ++
        "    return count + len(value)\n", "func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    const value = [1]\n" ++
        "    const count = my_take(copy(value))\n" ++
        "    return count + len(value)\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    const value = [1]\n" ++
        "    return my_take(value)\n", "func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    const value = [1]\n" ++
        "    return my_take(own value)\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepairWarnings("record Box:\n" ++
        "    items: int[]\n" ++
        "    name: str\n" ++
        "func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    const b = Box(items=[1], name=\"kept\")\n" ++
        "    const count = my_take(b.items)\n" ++
        "    return count + len(b.name)\n", "record Box:\n" ++
        "    items: int[]\n" ++
        "    name: str\n" ++
        "func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    mut b = Box(items=[1], name=\"kept\")\n" ++
        "    const count = my_take(take(mut b.items))\n" ++
        "    return count + len(b.name)\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("record Box:\n" ++
        "    items: int[]\n" ++
        "    name: str\n" ++
        "func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    const b = Box(items=[1], name=\"kept\")\n" ++
        "    return my_take(b.items)\n", "record Box:\n" ++
        "    items: int[]\n" ++
        "    name: str\n" ++
        "func my_take(own value: int[]) -> int:\n" ++
        "    return len(value)\n" ++
        "func main() -> int:\n" ++
        "    const b = Box(items=[1], name=\"kept\")\n" ++
        "    return my_take(own b.items)\n");
}
test "F6 generic concrete storage gets repairs but dependent moves remain shared" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    // A `mut` binding stored once from a place borrows it (D4), so each binding is written or given away to keep its refusal.
    try fxRepair("func count[T](value: T) -> int:\n" ++
        "    const gathered: int[] = [1]\n" ++
        "    mut order = gathered\n" ++
        "    append(mut order, 2)\n" ++
        "    return len(order)\n" ++
        "func main() -> int:\n" ++
        "    return count(1)\n", "func count[T](value: T) -> int:\n" ++
        "    const gathered: int[] = [1]\n" ++
        "    mut order = own gathered\n" ++
        "    append(mut order, 2)\n" ++
        "    return len(order)\n" ++
        "func main() -> int:\n" ++
        "    return count(1)\n");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = "func sink[T](own value: T) -> int:\n" ++
        "    return 1\n" ++
        "func count[T](own value: T) -> int:\n" ++
        "    mut moved = value\n" ++
        "    return sink(own moved)\n" ++
        "func main() -> int:\n" ++
        "    return count([1])\n" }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(!contains(checked.stderr, "\"fix\""));
}
test "F6 undeclared borrow points at the first missing lender rather than first borrowed return" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("func f(a: int[], b: int[], c: bool) -> int[] from a:\n" ++
        "    if c:\n" ++
        "        return a\n" ++
        "    return b\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    print(out, len(f([1], [2], False)))\n" ++
        "    return 0\n", .{ .code = "E_BORROW_UNDECLARED", .rule = "R4", .at = "b" });
}
test "F6 marker eligibility names container borrowed-call and mut-parameter causes" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("record Row:\n" ++
        "    items: int[]\n" ++
        "func my_take(xs: Row[]) -> int:\n" ++
        "    const items = own xs[0].items\n" ++
        "    return len(items)\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", .{ .code = "E_SINGLE_OWNER_BORROW", .rule = "B7", .message = "plain parameter `xs`" });
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("record Item:\n" ++
        "    name: str\n" ++
        "func pick(x: Item) -> Item from x:\n" ++
        "    return x\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    const l = Item(name=\"a\" + str(1))\n" ++
        "    const n = own pick(l).name\n" ++
        "    print(out, n)\n" ++
        "    return 0\n", .{ .code = "E_SINGLE_OWNER_BORROW", .rule = "R3", .message = "lent by the local `l`" });
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("record Box:\n" ++
        "    items: int[]\n" ++
        "func my_take(mut b: Box) -> int[]:\n" ++
        "    return own b.items\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", .{ .code = "E_SINGLE_OWNER_BORROW", .rule = "M1", .message = "`mut` parameter `b`" });
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("record Box:\n" ++
        "    items: int[]\n" ++
        "func my_take(b: Box) -> int:\n" ++
        "    const items = own b.items\n" ++
        "    return len(items)\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", .{ .code = "E_SINGLE_OWNER_BORROW", .rule = "B8", .message = "plain parameter `b`" });
}
test "F6 scalar and duplicate from refusals carry certain clause repairs" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("func size(a: int[]) -> int from a:\n" ++
        "    return len(a)\n" ++
        "func main() -> int:\n" ++
        "    return size([1])\n", "func size(a: int[]) -> int:\n" ++
        "    return len(a)\n" ++
        "func main() -> int:\n" ++
        "    return size([1])\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRepair("func choose(a: int[], b: int[]) -> int[] from b, a, a:\n" ++
        "    return a\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", "func choose(a: int[], b: int[]) -> int[] from b, a:\n" ++
        "    return a\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
}
test "F6 misplaced and callable from syntax explains its supported position" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("func first(a: str) -> str fails int from a:\n" ++
        "    return a\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", .{ .code = "E_SYNTAX", .message = "before `fails`" });
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxRefusal("func consume(callback: func(a: str) -> str from a):\n" ++
        "    pass\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", .{ .code = "E_SYNTAX", .message = "function types cannot declare borrowed results" });
}
test "F6 f-string pieces retain loans through later mutating pieces" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxFormatLoan("func g(mut t: str[]) -> str:\n" ++
        "    for i in range(300):\n" ++
        "        append(mut t, \"grow\" + str(i))\n" ++
        "    t = [\"new\" + str(1)]\n" ++
        "    return \"x\"\n" ++
        "func gi(mut t: str[]) -> int:\n" ++
        "    t = [\"new\" + str(1)]\n" ++
        "    return 0\n" ++
        "func two(a: str, b: str) -> int:\n" ++
        "    return len(a) + len(b)\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    mut t = [\"abc\" + str(1), \"def\"]\n" ++
        "    const s = f\"{t[0]}{g(mut t)}\"\n" ++
        "    print(out, s)\n" ++
        "    return 0\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxFormatLoan("func g(mut t: str[]) -> str:\n" ++
        "    for i in range(300):\n" ++
        "        append(mut t, \"grow\" + str(i))\n" ++
        "    t = [\"new\" + str(1)]\n" ++
        "    return \"x\"\n" ++
        "func big() -> str:\n" ++
        "    mut s = \"\"\n" ++
        "    for i in range(2000):\n" ++
        "        s += \"a\"\n" ++
        "    return s\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    mut t = [big(), \"def\"]\n" ++
        "    const s = f\"{t[0]}{g(mut t)}\"\n" ++
        "    print(out, len(s), s[0:3], t[0])\n" ++
        "    return 0\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxFormatLoan("record R:\n" ++
        "    name: str\n" ++
        "func h(mut r: R) -> str:\n" ++
        "    r = R(name=\"new\" + str(1))\n" ++
        "    return \"x\"\n" ++
        "func big() -> str:\n" ++
        "    mut s = \"\"\n" ++
        "    for i in range(2000):\n" ++
        "        s += \"a\"\n" ++
        "    return s\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    mut r = R(name=big())\n" ++
        "    const s = f\"{r.name}{h(mut r)}\"\n" ++
        "    print(out, len(s), r.name)\n" ++
        "    return 0\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxFormatLoan("func h(mut r: str) -> str:\n" ++
        "    r = \"new\" + str(1)\n" ++
        "    return \"x\"\n" ++
        "func big() -> str:\n" ++
        "    mut s = \"\"\n" ++
        "    for i in range(2000):\n" ++
        "        s += \"a\"\n" ++
        "    return s\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    mut r = big()\n" ++
        "    const s = f\"{r}{h(mut r)}\"\n" ++
        "    print(out, len(s), r)\n" ++
        "    return 0\n");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try fxFormatLoan("func h(mut r: str) -> str:\n" ++
        "    r = \"new\" + str(1)\n" ++
        "    return \"x\"\n" ++
        "func big() -> str:\n" ++
        "    mut s = \"\"\n" ++
        "    for i in range(2000):\n" ++
        "        s += \"a\"\n" ++
        "    return s\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    mut r = big()\n" ++
        "    print(out, f\"{r[0:5]}-{h(mut r)}\", r)\n" ++
        "    return 0\n");
}
fn fxFormatLoan(text: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = text }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "\"code\":\"E_SINGLE_OWNER_OVERLAP\""));
    try testing.expect(contains(checked.stderr, "\"rule\":\"M5\"") or contains(checked.stderr, "\"rule\":\"R2\""));
}

const F6FromDiagnostic = struct {
    code: []const u8,
    rule: ?[]const u8 = null,
    message: []const u8,
    at: []const u8,
    removed: ?[]const u8 = null,
};

/// Pin source errors and their exact certain deletion, or the deliberate lack of a fix.
fn f6FromRefusal(backing: std.mem.Allocator, text: []const u8, expected: F6FromDiagnostic) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    var project = try Project.init(&.{.{ .path = "main.selka", .data = text }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    var lines = std.mem.splitScalar(u8, checked.stderr, '\n');
    const line = lines.next() orelse return error.TestUnexpectedResult;
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), line, .{});
    try testing.expectEqualStrings("diagnostic-v1", parsed.value.object.get("version").?.string);
    const item = parsed.value.object.get("diagnostic").?.object;
    try testing.expectEqualStrings("error", item.get("severity").?.string);
    try testing.expectEqualStrings(expected.code, item.get("code").?.string);
    if (expected.rule) |rule| {
        try testing.expectEqualStrings(rule, item.get("rule").?.string);
    } else try testing.expect(item.get("rule") == null);
    try testing.expect(contains(item.get("message").?.string, expected.message));
    const location = item.get("location").?.object.get("bytes").?.object;
    const start: usize = @intCast(location.get("start").?.integer);
    const end: usize = @intCast(location.get("end").?.integer);
    try testing.expectEqualStrings(expected.at, text[start..end]);
    if (expected.removed) |removed| {
        const edits = item.get("fix").?.object.get("edits").?.array.items;
        try testing.expectEqual(@as(usize, 1), edits.len);
        const edit = edits[0].object;
        try testing.expectEqualStrings("main.selka", std.fs.path.basename(edit.get("path").?.string));
        const bytes = edit.get("bytes").?.object;
        const edit_start: usize = @intCast(bytes.get("start").?.integer);
        const edit_end: usize = @intCast(bytes.get("end").?.integer);
        try testing.expectEqualStrings(removed, text[edit_start..edit_end]);
        try testing.expectEqualStrings("", edit.get("text").?.string);
    } else {
        try testing.expect(item.get("fix") == null);
        const fixed = try project.run("fix", "main.selka", &.{});
        defer fixed.deinit();
        try testing.expectEqual(@as(u8, 1), fixed.status);
        const unchanged = try project.read("main.selka");
        defer backing.free(unchanged);
        try testing.expectEqualStrings(text, unchanged);
    }
}

test "F6 scalar from clauses report R4 and remove only the clause before fails" {
    const source = @embedFile("fixtures/fix-migration/from_details/main.selka");
    try f6FromRefusal(testing.allocator, source, .{ .code = "E_BORROW_SOURCE", .rule = "R4", .message = "contains no managed storage", .at = "int", .removed = " from a" });
    try fxRepair(source,
        \\func size(a: int[]) -> int fails str: # keep the failure contract
        \\    return len(a)
        \\func choose(a: int[], b: int[]) -> int[] from b, a:
        \\    _ = b
        \\    return a
        \\func main() -> int:
        \\    const left = [1, 2]
        \\    const right = [3]
        \\    const selected = choose(left, right)
        \\    match size(selected):
        \\        case Ok(count):
        \\            return count
        \\        case Err(error):
        \\            return len(error)
        \\# lint: allow-file match-else reason="this corpus pins its own migration; the flat forms have unwrapping-match.selka"
        \\# lint: allow-file match-is reason="this corpus pins its own migration; the flat forms have unwrapping-match.selka"
        \\
    );
}

test "F6 optional scalar successes ignore managed failure payloads for from eligibility" {
    const source =
        // migrate-embedded: skip intentional F6 scalar optional from refusal and exact repair.
        \\func size(a: int[]) -> int? from a fails str:
        \\    return Some(len(a))
        \\func main() -> int:
        \\    return 0
    ;
    try f6FromRefusal(testing.allocator, source, .{ .code = "E_BORROW_SOURCE", .rule = "R4", .message = "contains no managed storage", .at = "int?", .removed = " from a" });
    try fxRepair(source,
        \\func size(a: int[]) -> int? fails str:
        \\    return Some(len(a))
        \\func main() -> int:
        \\    return 0
    );
}

test "F6 duplicate from deletion preserves source order and the later failure clause" {
    const source =
        // migrate-embedded: skip intentional F6 duplicate from refusal and exact repair.
        \\func choose(a: int[], b: int[]) -> int[] from b, a, a fails str:
        \\    _ = b
        \\    return a
        \\func main() -> int:
        \\    return 0
    ;
    try f6FromRefusal(testing.allocator, source, .{ .code = "E_BORROW_SOURCE", .rule = "R4", .message = "duplicate source", .at = "a", .removed = ", a" });
    try fxRepair(source,
        \\func choose(a: int[], b: int[]) -> int[] from b, a fails str:
        \\    _ = b
        \\    return a
        \\func main() -> int:
        \\    return 0
    );
}

test "F6 duplicate contextual from names repair without changing other names" {
    const source =
        // migrate-embedded: skip intentional F6 duplicate contextual from refusal and exact repair.
        \\func choose(from: str, other: str) -> str from from,from, other:
        \\    _ = other
        \\    return from
        \\func main() -> int:
        \\    return 0
    ;
    try f6FromRefusal(testing.allocator, source, .{ .code = "E_BORROW_SOURCE", .rule = "R4", .message = "duplicate source", .at = "from", .removed = ",from" });
    try fxRepair(source,
        \\func choose(from: str, other: str) -> str from from, other:
        \\    _ = other
        \\    return from
        \\func main() -> int:
        \\    return 0
    );
}

test "F6 from after fails is syntax only and fix leaves it unchanged" {
    try f6FromRefusal(testing.allocator,
        // migrate-embedded: skip intentional F6 misplaced from syntax with no certain repair.
        \\func first(a: str) -> str fails int from a:
        \\    return a
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SYNTAX", .message = "before `fails`", .at = "from" });
}

test "F6 callable from on either side of fails is syntax only without a fix" {
    try f6FromRefusal(testing.allocator,
        // migrate-embedded: skip intentional F6 callable from syntax with no certain repair.
        \\func consume(callback: func(a: str) -> str from a fails int):
        \\    pass
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SYNTAX", .message = "function types cannot declare borrowed results", .at = "from" });
    try f6FromRefusal(testing.allocator,
        // migrate-embedded: skip intentional F6 callable from syntax with no certain repair.
        \\func consume(callback: func(a: str) -> str fails int from a):
        \\    pass
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SYNTAX", .message = "function types cannot declare borrowed results", .at = "from" });
}

test "F6 managed wrapped declarations and generic scalar instances retain from contracts" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func identity[T](value: T) -> T from value:
        \\    return value
        \\func maybe(value: str) -> str? from value fails str:
        \\    return Some(value)
        \\func main() -> int:
        \\    const values = [1, 2]
        \\    const borrowed = identity(values)
        \\    return identity(1) + len(borrowed)
    }});
    defer project.deinit();
    const fresh = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer fresh.deinit();
    try testing.expectEqual(@as(u8, 0), fresh.status);
    const cached = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer cached.deinit();
    try testing.expectEqual(@as(u8, 0), cached.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix rewrites a literal if chain on a plain bytes to a match and leaves one on an option alone, so the program still checks" {
    const original = @embedFile("fixtures/fix-migration/literal-match-option.selka");
    const expected = @embedFile("fixtures/fix-migration/literal-match-option.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    // The chains on `bytes?` and `str?`, the one that opens with `is None` and the byte sets on an `int?` and a `float` draw no warning: a literal arm and `in b"..."` are refused there.
    const before_check = try project.run("check", "main.selka", &.{});
    defer before_check.deinit();
    try testing.expectEqual(@as(u8, 0), before_check.status);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, before_check.stderr, "W_LITERAL_MATCH"));
    const before_run = try project.run("run", "main.selka", &.{});
    defer before_run.deinit();
    try testing.expectEqual(@as(u8, 0), before_run.status);
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 1 edit (W_LITERAL_MATCH)"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 1 edit (W_LITERAL_MATCH)"));
    try testing.expect(!contains(fixed.stderr, "E_LITERAL_ARM"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    // The repaired program checks, nothing is left to fix, and it prints what it printed before.
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stderr, "W_LITERAL_MATCH"));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(before_run.stdout, ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix moves a record at its last use in a match arm and borrows a const bound to a copy of an element, and the program prints the same lines" {
    const original = @embedFile("fixtures/fix-migration/needless-copy-aggregates.selka");
    const expected = @embedFile("fixtures/fix-migration/needless-copy-aggregates.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const before_run = try project.run("run", "main.selka", &.{});
    defer before_run.deinit();
    try testing.expectEqual(@as(u8, 0), before_run.status);
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 4 edits (W_NEEDLESS_COPY)"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 4 edits (W_NEEDLESS_COPY)"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    // The repaired program checks with nothing left to fix, and prints what it printed with the copies.
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stderr, "W_NEEDLESS_COPY"));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(before_run.stdout, ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix takes the list a call returns and moves each element out of it (F-75, FR25), and leaves the copies that are not certain" {
    const original = @embedFile("fixtures/fix-migration/fresh-loop-moves.selka");
    const expected = @embedFile("fixtures/fix-migration/fresh-loop-moves.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const before_run = try project.run("run", "main.selka", &.{});
    defer before_run.deinit();
    try testing.expectEqual(@as(u8, 0), before_run.status);
    const preview = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka: 10 edits (W_NEEDLESS_COPY)"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 10 edits (W_NEEDLESS_COPY)"));
    try testing.expect(contains(fixed.stdout, "fix: 10 edits in 1 file over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    // The repaired program checks, and the copy whose move is not certain because a loop around it runs it twice keeps its
    // `W_COPY_MOVE` hint; the copy of an element that a view still reads draws none, since the advised edit is refused (FR26).
    const checked = try project.run("check", "main.selka", &.{"--warnings"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stderr, "W_NEEDLESS_COPY"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, checked.stderr, "warning[W_COPY_MOVE]"));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(before_run.stdout, ran.stdout);
}

/// Each error a check printed, one `file:line:column CODE` line per error (the file's base name), in the order printed.
fn errorSites(text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(testing.allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const at = std.mem.indexOf(u8, line, ": error[") orelse continue;
        const close = std.mem.indexOfScalarPos(u8, line, at, ']') orelse continue;
        try out.print(testing.allocator, "{s} {s}\n", .{ std.fs.path.basename(line[0..at]), line[at + ": error[".len .. close] });
    }
    return out.toOwnedSlice(testing.allocator);
}

/// `check` one project and compare the errors it printed with `expected` (`errorSites`).
fn checkSites(files: []const File, entry: []const u8, expected: []const u8) !void {
    var project = try Project.init(files);
    defer project.deinit();
    const checked = try project.run("check", entry, &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    const sites = try errorSites(checked.stderr);
    defer testing.allocator.free(sites);
    try testing.expectEqualStrings(expected, sites);
}

test "check reports every independent type error of a body in one run, in source order (F-RC-214)" {
    try checkSites(&.{.{ .path = "types.selka", .data = @embedFile("fixtures/all-errors/independent_types.selka") }}, "types.selka",
        \\types.selka:3:18 E_TYPE
        \\types.selka:4:17 E_TYPE
        \\types.selka:5:5 E_UNKNOWN_FUNCTION
        \\types.selka:10:12 E_UNKNOWN_NAME
        \\
    );
}

test "check reports every missing own of a file in one run, three in one call (F-RA-507, F-RA-613)" {
    try checkSites(&.{.{ .path = "own.selka", .data = @embedFile("fixtures/all-errors/independent_own.selka") }}, "own.selka",
        \\own.selka:17:21 E_OWN_MARKER
        \\own.selka:17:26 E_OWN_MARKER
        \\own.selka:17:31 E_OWN_MARKER
        \\own.selka:23:22 E_OWN_MARKER
        \\own.selka:23:39 E_OWN_MARKER
        \\
    );
}

test "check reports every borrowed value a mut binding keeps in one run, two in one body" {
    try checkSites(&.{.{ .path = "borrow.selka", .data = @embedFile("fixtures/all-errors/independent_borrow.selka") }}, "borrow.selka",
        \\borrow.selka:9:5 E_SINGLE_OWNER_BORROW
        \\borrow.selka:11:5 E_SINGLE_OWNER_BORROW
        \\borrow.selka:17:5 E_SINGLE_OWNER_BORROW
        \\
    );
}

test "check reports the ownership errors of the bodies that checked beside a type error, in source order, and leaves its callers unjudged" {
    try checkSites(&.{.{ .path = "mixed.selka", .data = @embedFile("fixtures/all-errors/mixed.selka") }}, "mixed.selka",
        \\mixed.selka:9:14 E_TYPE
        \\mixed.selka:15:22 E_OWN_MARKER
        \\mixed.selka:15:31 E_OWN_MARKER
        \\mixed.selka:26:22 E_OWN_MARKER
        \\
    );
}

test "check reports one error for each root cause: a moved list used three times, a failed binding used twice" {
    try checkSites(&.{.{ .path = "cascade.selka", .data = @embedFile("fixtures/all-errors/cascade.selka") }}, "cascade.selka",
        \\cascade.selka:5:12 E_SINGLE_OWNER_MOVED
        \\cascade.selka:11:18 E_TYPE
        \\
    );
}

test "a project check reports a type error in one module beside the ownership errors of another" {
    try checkSites(&.{
        .{ .path = "selka.json", .data = "{\"version\": 1}\n" },
        .{ .path = "main.selka", .data = "import names\nimport pairs\n\nfunc main() -> int:\n    return len(pairs.pair(b\"x\").left) + names.count()\n" },
        .{ .path = "names.selka", .data = "public func count() -> int:\n    return missing\n" },
        .{ .path = "pairs.selka", .data = "public record Pair:\n    left: bytes\n    right: bytes\n\npublic func pair(name: bytes) -> Pair:\n    const l = name + b\"l\"\n    const r = name + b\"r\"\n    return Pair(left=l, right=r)\n" },
    }, "main.selka",
        \\names.selka:2:12 E_UNKNOWN_NAME
        \\pairs.selka:8:22 E_OWN_MARKER
        \\pairs.selka:8:31 E_OWN_MARKER
        \\
    );
}

/// A module of `count` functions, each refused twice for storing a borrowed parameter (`own name`, `own other`), and the
/// errors `check` prints for it (`errorSites`), in source order. Each refusal's certain repair is a copy, so the recovering
/// check rewrites each function twice.
fn borrowRefusals(a: std.mem.Allocator, count: usize) !struct { module: []const u8, sites: []const u8 } {
    var module: std.ArrayList(u8) = .empty;
    var sites: std.ArrayList(u8) = .empty;
    try module.appendSlice(a, "public record Pair:\n    left: bytes\n    right: bytes\n\n");
    for (0..count) |index| {
        try module.print(a, "public func make_{d}(name: bytes, other: bytes) -> Pair:\n    return Pair(left=own name, right=own other)\n\n", .{index});
        const line = 6 + 3 * index;
        try sites.print(a, "pairs.selka:{d}:22 E_SINGLE_OWNER_BORROW\npairs.selka:{d}:38 E_SINGLE_OWNER_BORROW\n", .{ line, line });
    }
    return .{ .module = module.items, .sites = sites.items };
}

test "a project check with a type error in one module and 600 ownership errors in another reports them all under a 192 MiB ceiling" {
    // Every refused function's repairs copy the whole program's node and statement tables. They were made in the arena the
    // check's diagnostics live in, so none was released before the check ended: this project needed about 520 MiB, and with
    // the 8 GiB default a large port died with `host failure: OutOfMemory`. Now one function's copies are released when it
    // is done, and the check needs about 40 MiB.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const generated = try borrowRefusals(a, 300);
    var project = try Project.init(&.{
        .{ .path = "selka.json", .data = "{\"version\": 1}\n" },
        .{ .path = "main.selka", .data = "import pairs\nimport tables\n\nfunc main() -> int:\n    const p = pairs.make_0(b\"a\", b\"b\")\n    mut cache: dict[bytes, bytes[]] = {}\n    const xs = tables.drain(mut cache, b\"k\")\n    return len(p.left) + len(xs)\n" },
        .{ .path = "pairs.selka", .data = generated.module },
        .{ .path = "tables.selka", .data = "public func drain(mut cache: dict[bytes, bytes[]], key: bytes) -> bytes[]:\n    return take(mut cache[key])\n" },
    });
    defer project.deinit();
    var environment = try @import("test_paths").privateEnvironment(a);
    try environment.put("SELKA_HOST_MEMORY_LIMIT", "192M");
    const checked = try project.runIn(&environment, "check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expect(!contains(checked.stderr, "OutOfMemory"));
    try testing.expectEqual(@as(u8, 1), checked.status);
    const sites = try errorSites(checked.stderr);
    defer testing.allocator.free(sites);
    try testing.expectEqualStrings(try std.mem.concat(a, u8, &.{ generated.sites, "tables.selka:2:17 E_ASSIGNMENT_TARGET\n" }), sites);
}

test "fix settles a file of independent ownership repairs in one round, and the program runs" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = @embedFile("fixtures/all-errors/fix_one_round.selka") }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed main.selka: 11 edits (E_OWN_MARKER, E_SINGLE_OWNER_BORROW)\nfix: 11 edits in 1 file over 1 round\n", fixed.stdout);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 10), ran.status);
}

const module_user =
    \\import helpers
    \\
    \\
    \\public func twice() -> int:
    \\    mut xs: int[] = []
    \\    helpers.grow(xs)
    \\    helpers.grow(xs)
    \\    return len(xs)
    \\
;
const module_helpers =
    \\import unused
    \\
    \\
    \\public func grow(mut xs: int[]) -> Unit:
    \\    append(mut xs, 1)
    \\
;

// spec-case: FIX-FILE-1
test "CLI fix of a module repairs that file only and names what it left in the modules it imports" {
    var project = try Project.init(&.{
        .{ .path = "user.selka", .data = module_user },
        .{ .path = "helpers.selka", .data = module_helpers },
        .{ .path = "unused.selka", .data = unused_module },
    });
    defer project.deinit();
    const preview = try project.run("fix", "user.selka", &.{ "--check", "--warnings" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix user.selka: 2 edits (E_MUTATION_MARKER)"));
    try testing.expect(!contains(preview.stdout, "helpers.selka"));
    const fixed = try project.run("fix", "user.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed user.selka: 2 edits (E_MUTATION_MARKER)"));
    try testing.expect(!contains(fixed.stdout, "fixed helpers.selka"));
    try testing.expect(contains(fixed.stdout, "fix: left 1 fix in 1 other file that user.selka imports"));
    try expectFile(&project, "helpers.selka", module_helpers);
    const user = try project.read("user.selka");
    defer testing.allocator.free(user);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, user, "helpers.grow(mut xs)"));
    // What is left in the import is not this file's to change: `--check` finds nothing to do here and says where the rest is.
    const rest = try project.run("fix", "user.selka", &.{ "--check", "--warnings" });
    defer rest.deinit();
    try testing.expectEqual(@as(u8, 0), rest.status);
    try testing.expectEqualStrings("fix: nothing to fix\nfix: left 1 fix in 1 other file that user.selka imports; `selka fix --imports user.selka` repairs them too\n", rest.stdout);
}

// spec-case: FIX-FILE-1
test "CLI fix --imports repairs the modules a file imports too, and a program entry always does" {
    var project = try Project.init(&.{
        .{ .path = "user.selka", .data = module_user },
        .{ .path = "helpers.selka", .data = module_helpers },
        .{ .path = "unused.selka", .data = unused_module },
    });
    defer project.deinit();
    const fixed = try project.run("fix", "user.selka", &.{ "--imports", "--warnings" });
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed user.selka: 2 edits (E_MUTATION_MARKER)"));
    try testing.expect(contains(fixed.stdout, "fixed helpers.selka: 1 edit (W_UNUSED_IMPORT)"));
    try testing.expect(!contains(fixed.stdout, "left"));
    const helpers = try project.read("helpers.selka");
    defer testing.allocator.free(helpers);
    try testing.expect(!contains(helpers, "import unused"));
    const again = try project.run("fix", "user.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

// spec-case: FIX-FILE-1
test "CLI fix of a test file leaves the modules it imports alone, and a directory still repairs them all" {
    var project = try Project.init(&.{
        .{ .path = "user_test.selka", .data = "import helpers\n\n\npublic func test_grows() -> bool:\n    mut xs: int[] = []\n    helpers.grow(xs)\n    return len(xs) == 1\n" },
        .{ .path = "helpers.selka", .data = module_helpers },
        .{ .path = "unused.selka", .data = unused_module },
    });
    defer project.deinit();
    const alone = try project.run("fix", "user_test.selka", &.{});
    defer alone.deinit();
    try testing.expectEqual(@as(u8, 0), alone.status);
    try testing.expect(contains(alone.stdout, "fixed user_test.selka: 1 edit (E_MUTATION_MARKER)"));
    try testing.expect(!contains(alone.stdout, "fixed helpers.selka"));
    try expectFile(&project, "helpers.selka", module_helpers);
    const all = try project.run("fix", ".", &.{});
    defer all.deinit();
    try testing.expectEqual(@as(u8, 0), all.status);
    try testing.expect(contains(all.stdout, "fixed helpers.selka: 1 edit (W_UNUSED_IMPORT)"));
    try testing.expect(!contains(all.stdout, "left"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix deletes the value of return Unit(), return Unit and return unit in one round (F-41)" {
    const original = @embedFile("fixtures/fix-migration/return-unit.selka");
    const wanted = @embedFile("fixtures/fix-migration/return-unit.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "a function that returns `Unit` ends with a bare `return`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 3 edits in 1 file over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

test "a binding named like an imported module names the module and its import (F-10)" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\import strings
        \\import json
        \\
        \\func count(strings: str[]) -> int:
        \\    return len(strings)
        \\
        \\
        \\func walk(xs: str[]) -> int:
        \\    mut n = 0
        \\    for json in xs:
        \\        n += len(json)
        \\    return n
        \\
        \\
        \\func main() -> int:
        \\    return count(["a"]) + walk(["b"])
        \\
    }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "parameter `strings` would hide the imported module `strings`"));
    try testing.expect(contains(refused.stderr, "main.selka:1:8: imported here"));
    try testing.expect(contains(refused.stderr, "iteration binding `json` would hide the imported module `json`"));
}

test "a module missing under a parent's selka.json names the import root and the import that reaches it (F-6)" {
    var project = try Project.init(&.{
        .{ .path = "selka.json", .data = "{\"version\": 1}\n" },
        .{ .path = "src/lib.selka", .data = "public func double(n: int) -> int:\n    return n * 2\n" },
        .{ .path = "src/lib_test.selka", .data = "import lib\n\npublic func test_double() -> bool:\n    return lib.double(2) == 4\n" },
    });
    defer project.deinit();
    const checked = try project.run("check", "src/lib_test.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "cannot load lib.selka: there is no `lib.selka` under the import root"));
    try testing.expect(contains(checked.stderr, "selka.json`); `src/lib.selka` is beside the importing module: import it as `src.lib`"));
    // A directory run does not stop at the file: it prints the diagnostic that explains it and reports the file as failed.
    const tested = try project.run("test", "src", &.{});
    defer tested.deinit();
    try testing.expectEqual(@as(u8, 1), tested.status);
    try testing.expect(!contains(tested.stderr, "directory test discovery failed"));
    try testing.expect(contains(tested.stderr, "import it as `src.lib`"));
    try testing.expect(contains(tested.stdout, "lib_test.selka: failed to check or build, so no tests ran"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix leaves a try in an operand as written, and a program it once hoisted keeps running the same (F-3, TRY-2)" {
    const original = @embedFile("fixtures/fix-migration/try-hoist.selka");
    const hoisted = @embedFile("fixtures/fix-migration/try-hoist.expected.selka");
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = original }, .{ .path = "hoisted.selka", .data = hoisted } });
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(!contains(fixed.stdout, "edits in"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(original, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("3\n5\nhead: x;\n3\n", ran.stdout);
    const ran_hoisted = try project.run("run", "hoisted.selka", &.{});
    defer ran_hoisted.deinit();
    try testing.expectEqual(@as(u8, 0), ran_hoisted.status);
    try testing.expectEqualStrings(ran.stdout, ran_hoisted.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix replaces the raw network builtin with the operation that sends the same request (FR5a)" {
    const original = @embedFile("fixtures/fix-migration/raw-network.selka");
    const wanted = @embedFile("fixtures/fix-migration/raw-network.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:9:15: error[E_INTERNAL_NAME]: `acquire_resource` on a Network is reserved for the standard library"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 3 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("connected\naccepted\nno poller 2\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes else Err(_) for a bare else or else None over a call that fails (F-60)" {
    const original = @embedFile("fixtures/fix-migration/else-on-result.selka");
    const wanted = @embedFile("fixtures/fix-migration/else-on-result.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "`half(value)` can fail with str, so the `else` must say what it does with the failure: " ++
        "`else Err(_):` drops it and `else Err(reason):` binds it to use (a bare `else:` takes only an Option's `None`)"));
    try testing.expect(contains(refused.stderr, "main.selka:7:6: the called function, which can fail"));
    try testing.expect(!contains(refused.stderr, "main.selka:1:1"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 4 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("3 5 4 7 3\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes if CALL is Err(e) for a call statement followed by else (F-76)" {
    const original = @embedFile("fixtures/fix-migration/else-statement.selka");
    const wanted = @embedFile("fixtures/fix-migration/else-statement.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:24:22: error[E_SYNTAX]: `else` needs a value to bind, and a statement that is only " ++
        "`check(value)` has none: write `if check(value) is Err(_):` when the call gives nothing back, or drop or keep its value with " ++
        "`_ = check(value) else Err(_):` or `const NAME = check(value) else Err(_):`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 8 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("check: negative\nparse: negative\nfind: nothing\n4\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix inserts the type of a module constant written without one (SP1-F-3, W3-F-4)" {
    const original = @embedFile("fixtures/fix-migration/module-constant.selka");
    const wanted = @embedFile("fixtures/fix-migration/module-constant.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:3:13: error[E_SYNTAX]: a module constant needs its type: write `const LIMIT: int = 40`"));
    try testing.expect(contains(refused.stderr, "main.selka:4:21: error[E_SYNTAX]: a module constant needs its type: write `const OFFSET: int = -2`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 5 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 40), ran.status);
    try testing.expectEqualStrings("hello\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes the comparison that x in range(a, b) means (SP3-F-11)" {
    const original = @embedFile("fixtures/fix-migration/range-membership.selka");
    const wanted = @embedFile("fixtures/fix-migration/range-membership.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:4:17: error[E_UNKNOWN_FUNCTION]: `range` is a loop source (`for i in range(a, b):`), " ++
        "not a collection, so `in` cannot test against it: write the comparison `0 <= x < hi`"));
    try testing.expect(contains(refused.stderr, "write the comparison `x < lo or hi <= x`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 3 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 7), ran.status);
}

/// Two programs that reach `lib/util/text.selka` and `lib/shout.selka`, `main.selka` through the links `util` and `shout.selka` and
/// `direct.selka` by the files' own paths: the checks print and repair one file under two paths.
const linked_program =
    \\import shout
    \\import util.text as text
    \\
    \\
    \\func main() -> int:
    \\    if text.small(3) and shout.loud(2):
    \\        return 0
    \\    return 1
    \\
;

const direct_program =
    \\import lib.shout as shout
    \\import lib.util.text as text
    \\
    \\
    \\func main() -> int:
    \\    if text.small(4) and shout.loud(3):
    \\        return 0
    \\    return 1
    \\
;

/// The project of the symbolic-link tests: one range-chain repair in each linked file, reached by two programs by two paths.
fn linkedProject() !Project {
    var project = try Project.init(&.{
        .{ .path = "lib/util/text.selka", .data = "public func small(x: int) -> bool:\n    return x >= 0 and x < 10\n" },
        .{ .path = "lib/shout.selka", .data = "public func loud(x: int) -> bool:\n    return x >= 1 and x <= 5\n" },
        .{ .path = "direct.selka", .data = direct_program },
        .{ .path = "main.selka", .data = linked_program },
    });
    errdefer project.deinit();
    try project.temp.dir.symLink(testing.io, "lib/util", "util", .{ .is_directory = true });
    try project.temp.dir.symLink(testing.io, "lib/shout.selka", "shout.selka", .{});
    return project;
}

test "CLI fix edits a file two programs reach through a linked directory and a linked file once, under its real path (FR14)" {
    var project = try linkedProject();
    defer project.deinit();
    const planned = try project.run("fix", ".", &.{"--check"});
    defer planned.deinit();
    try testing.expectEqual(@as(u8, 1), planned.status);
    try testing.expectEqualStrings("would fix lib/shout.selka: 1 edit (W_RANGE_CHAIN)\nwould fix lib/util/text.selka: 1 edit (W_RANGE_CHAIN)\n" ++
        "fix --check: 2 edits in 2 files would change\n", planned.stdout);
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 2 edits in 2 files over 1 round"));
    const text = try project.read("lib/util/text.selka");
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("public func small(x: int) -> bool:\n    return 0 <= x < 10\n", text);
    const shout = try project.read("lib/shout.selka");
    defer testing.allocator.free(shout);
    try testing.expectEqualStrings("public func loud(x: int) -> bool:\n    return 1 <= x <= 5\n", shout);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

test "CLI fix prints a diagnostic two programs report under two paths to one linked file once (FR14)" {
    var project = try linkedProject();
    defer project.deinit();
    // A refusal in the linked file, which each program reports under the path it reached the file by.
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "lib/shout.selka", .data = "public func loud(x: int) -> bool:\n    return x >= 1 and x <= 5 and missing\n" });
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, fixed.stderr, "error[E_UNKNOWN_NAME]"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes the discard for a case arm that binds nothing of a payload, builtin, declared and generic (FR14)" {
    const original = @embedFile("fixtures/fix-migration/case-payload.selka");
    const wanted = @embedFile("fixtures/fix-migration/case-payload.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:34:14: error[E_PATTERN_PAYLOAD]: `case Ok` names a case that carries int, so the " ++
        "pattern must say what the arm does with it: `case Ok(_):` drops it and `case Ok(value):` binds it to use"));
    try testing.expect(contains(refused.stderr, "`case ok` names a case that carries int"));
    try testing.expect(contains(refused.stderr, "main.selka:4:5: variant declared here"));
    try testing.expect(contains(refused.stderr, "error[E_NAMED_PATTERN]: `case circle` names a case with the field `radius: float`, so the " ++
        "pattern must say what the arm does with it: `case circle(..):` drops it and `case circle(radius):` binds it to use"));
    try testing.expect(contains(refused.stderr, "`case Some` names a case that carries T,"));
    try testing.expect(!contains(refused.stderr, "payload variants require a binding"));
    try testing.expect(!contains(refused.stderr, "main.selka:1:1"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 7 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("0 1 1 0 1 -7\n0 4 1 0\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix flattens a match that only unwraps an Option or a Result, leaves the uncertain ones, and runs the same (FR20)" {
    const original = @embedFile("fixtures/fix-migration/unwrapping-match.selka");
    const wanted = @embedFile("fixtures/fix-migration/unwrapping-match.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const before = try project.run("run", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 0), before.status);
    const warned = try project.run("check", "main.selka", &.{"--warnings"});
    defer warned.deinit();
    try testing.expectEqual(@as(u8, 0), warned.status);
    try testing.expect(contains(warned.stderr, "main.selka:40:5: warning[W_MATCH_ELSE]: this `match` only unwraps `half(n)` and its `None` arm " ++
        "leaves: `const h = half(n) else:` with that block, then the other arm's statements, says the same without the `match`"));
    try testing.expect(contains(warned.stderr, "`const value = parse(n) else Err(e):` with that block"));
    try testing.expect(contains(warned.stderr, "`const value = parse(n) else Err(_):` with that block"));
    try testing.expect(contains(warned.stderr, "warning[W_MATCH_IS]: this `match` only unwraps `half(n)` and its other arm does nothing: " ++
        "`if half(n) is Some(h):` says the same without the `match`"));
    try testing.expect(contains(warned.stderr, "`if parse(n) is Err(e):` says the same"));
    try testing.expectEqual(@as(usize, 15), std.mem.count(u8, warned.stderr, "warning[W_MATCH_ELSE]"));
    try testing.expectEqual(@as(usize, 5), std.mem.count(u8, warned.stderr, "warning[W_MATCH_IS]"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, warned.stderr, "warning[W_OPTION_TRY]"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 23 edits in 1 file over 5 rounds"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(before.stdout, ran.stdout);
    try testing.expectEqualStrings("4 0 8 40 21 -1 6\n2 0 4 -1 2 106 3 8 1000\n2 10 Some(5) None Some(3) Ok(Some(2)) Ok(None) 2 1\n3 0 2 5 True\n", ran.stdout);
    const clean = try project.run("check", "main.selka", &.{"--warnings"});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "W_MATCH_"));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const formatted = try project.run("fmt", "main.selka", &.{});
    defer formatted.deinit();
    try testing.expectEqualStrings(wanted, formatted.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI check names both long unwrapping forms of the F-69 program and none in the standard library, and fix writes the flat forms (FR20)" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\import strings
        \\
        \\
        \\func half(n: int) -> int?:
        \\    if n % 2 != 0:
        \\        return None
        \\    return Some(n // 2)
        \\
        \\
        \\func leaves(n: int) -> int:
        \\    match half(n):
        \\        case Some(h):
        \\            const more = h + 1
        \\            return more
        \\        case None:
        \\            return 0
        \\
        \\
        \\func adds(n: int) -> int:
        \\    mut total = n
        \\    match half(n):
        \\        case Some(h):
        \\            total = total + h
        \\        case None:
        \\            pass
        \\    return total
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, strings.join([str(leaves(6)), str(adds(4))], " "))
        \\    return 0
        \\
    }});
    defer project.deinit();
    const warned = try project.run("check", "main.selka", &.{"--warnings"});
    defer warned.deinit();
    try testing.expectEqual(@as(u8, 0), warned.status);
    try testing.expect(contains(warned.stderr, "main.selka:11:5: warning[W_MATCH_ELSE]"));
    try testing.expect(contains(warned.stderr, "main.selka:21:5: warning[W_MATCH_IS]"));
    try testing.expect(!contains(warned.stderr, "@stdlib/"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "func leaves(n: int) -> int:\n    const h = half(n) else:\n        return 0\n    const more = h + 1\n    return more\n"));
    try testing.expect(contains(after, "    mut total = n\n    if half(n) is Some(h):\n        total = total + h\n    return total\n"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqualStrings("4 6\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix rewrites the removed contains method for a set, dictionary, text, bytes and list receiver (FR19)" {
    const original = @embedFile("fixtures/fix-migration/contains-method.selka");
    const wanted = @embedFile("fixtures/fix-migration/contains-method.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_REMOVED_SPELLING]: `seen.contains(name)` was removed for sets; use `name in seen`"));
    try testing.expect(contains(refused.stderr, "`h.table.contains(name)` was removed for dictionaries; use `name in h.table`"));
    try testing.expect(contains(refused.stderr, "`body.contains(part)` was removed for text; use `part in body`, which tests for a substring"));
    try testing.expect(contains(refused.stderr, "`data.contains(part)` was removed for bytes; use `part in data`, which tests for a byte or a run of bytes"));
    try testing.expect(contains(refused.stderr, "`xs.contains(value)` was removed for lists, which have no `in`; use `lists.contains(xs, value)`"));
    try testing.expect(!contains(refused.stderr, "was removed for dictionaries; use `key in mapping`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 15 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 11), ran.status);
}

// MSG-B 1: `strings.contains(text, part)` and `lists.contains(data, 10)` on text or bytes are told to write the operator `in`, and `selka
// fix` writes it where both operands are plain, with `not` kept as `not in`.
test "CLI fix rewrites strings.contains and lists.contains of text or bytes as the operator in (MSG-B)" {
    const source =
        \\import lists
        \\import strings
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const data = strings.encode("a\nb")
        \\    const text = "hello"
        \\    if lists.contains(data, 10):
        \\        print(out, "newline")
        \\    if not strings.contains(text, "xyz"):
        \\        print(out, "no xyz")
        \\    if strings.contains(text, "ell"):
        \\        print(out, "ell")
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:8:8: error[E_GENERIC_INFERENCE]: `lists.contains` is only for lists, and its first argument is bytes: " ++
        "whether bytes hold a byte or a run of bytes is the operator `in`: write `10 in data`"));
    try testing.expect(contains(refused.stderr, "main.selka:10:12: error[E_UNKNOWN_SYMBOL]: module `strings` declares no `contains`; " ++
        "whether text holds a part is the operator `in`: write `\"xyz\" in text` (`lists.contains` is only for lists)"));
    try testing.expect(!contains(refused.stderr, "the standard module `lists` declares a function `contains`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 3 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    if 10 in data:\n"));
    try testing.expect(contains(after, "    if \"xyz\" not in text:\n"));
    try testing.expect(contains(after, "    if \"ell\" in text:\n"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("newline\nno xyz\nell\n", ran.stdout);
}

// MSG-F: `lists.has` and `lists.includes` were answered with a module that cannot take a list, and `strings.has` with `argparse`. The refusal names
// `lists.contains` and the operator `in`, and `selka fix` writes them: the same meaning, so the edit is certain.
test "CLI fix renames lists.has and lists.includes and writes strings.has as the operator in (MSG-F)" {
    const source =
        \\import lists
        \\import strings
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const text = "hello"
        \\    const values = [4, 5, 6]
        \\    const held = lists.has(values, 6)
        \\    const kept = lists.includes(values, 5)
        \\    const part = strings.has(text, "ell")
        \\    print(out, f"{held} {kept} {part}")
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:8:18: error[E_UNKNOWN_SYMBOL]: module `lists` declares no `has`; whether a list holds a value is " ++
        "`lists.contains(values, value)` (a list has no operator `in`)"));
    try testing.expect(contains(refused.stderr, "module `strings` declares no `has`; whether text holds a part is the operator `in`: write `\"ell\" in text`"));
    try testing.expect(!contains(refused.stderr, "declares a function `has`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 3 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    const held = lists.contains(values, 6)\n"));
    try testing.expect(contains(after, "    const kept = lists.contains(values, 5)\n"));
    try testing.expect(contains(after, "    const part = \"ell\" in text\n"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("True True True\n", ran.stdout);
}

// R3-SMALLDIAG: a case of an enum named without its enum (`argparse.MissingValue` for `argparse.Error.MissingValue`) was only "declares no".
// When exactly one enum in reach has a case of that name the refusal says `did you mean `Enum.case`?` and `selka fix` writes it.
test "CLI fix writes an enum case with its enum when one enum has it, and leaves a case two enums have (R3-SMALLDIAG)" {
    const shapes =
        \\public enum Shape:
        \\    Circle(radius: int)
        \\    Square(side: int)
        \\
        \\
        \\public enum Mark:
        \\    Circle(color: int)
        \\    Dot
        \\
        \\
        \\public func measure(shape: Shape) -> int:
        \\    match shape:
        \\        case Circle(radius):
        \\            return radius
        \\        case Square(side):
        \\            return side
        \\
    ;
    const source =
        \\import shapes
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const a = shapes.Square(side=3)
        \\    const b = Square(side=4)
        \\    print(out, f"{shapes.measure(a)} {shapes.measure(b)}")
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = source }, .{ .path = "shapes.selka", .data = shapes } });
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:5:15: error[E_UNKNOWN_SYMBOL]: module `shapes` declares no `Square`; " ++
        "did you mean `shapes.Shape.Square`? A case of an enum is written with its enum"));
    try testing.expect(contains(refused.stderr, "main.selka:6:15: error[E_UNKNOWN_SYMBOL]: this module declares no `Square`; " ++
        "did you mean `shapes.Shape.Square`? A case of an enum is written with its enum"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 2 edits in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    const a = shapes.Shape.Square(side=3)\n"));
    try testing.expect(contains(after, "    const b = shapes.Shape.Square(side=4)\n"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("3 4\n", ran.stdout);
    // `Circle` is a case of two enums of the module: naming one is a guess, so the refusal is the plain one and nothing is written.
    var ambiguous = try Project.init(&.{ .{ .path = "main.selka", .data = "import shapes\n\n\nfunc main() -> int:\n    return shapes.measure(shapes.Circle(radius=1))\n" }, .{ .path = "shapes.selka", .data = shapes } });
    defer ambiguous.deinit();
    const plain = try ambiguous.run("check", "main.selka", &.{});
    defer plain.deinit();
    try testing.expectEqual(@as(u8, 1), plain.status);
    try testing.expect(contains(plain.stderr, "main.selka:5:27: error[E_UNKNOWN_SYMBOL]: module `shapes` declares no `Circle`\n"));
    try testing.expect(!contains(plain.stderr, "did you mean"));
}

// MSG-F: `strings.index` is answered with `strings.text_index`, which traps when the part is absent. `selka fix` runs after every check, and the author
// may have meant an answer of -1 or `None`, so no edit is made: the file is left as written and the refusal stays.
test "CLI fix leaves strings.index, strings.rindex and lists.index alone, and the refusal names the function (MSG-F)" {
    const source =
        \\import lists
        \\import strings
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const text = "hello"
        \\    const values = [4, 5, 6]
        \\    const at = strings.index(text, "l")
        \\    const last = strings.rindex(text, "l")
        \\    const place = lists.index(values, 5)
        \\    print(out, f"{at} {last} {place}")
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:8:16: error[E_UNKNOWN_SYMBOL]: module `strings` declares no `index`; the byte offset of the first occurrence is " ++
        "`strings.text_index(text, part)`, which traps when `part` is absent"));
    try testing.expect(contains(refused.stderr, "module `lists` declares no `index`; the position of the first equal element is `lists.index_of(values, value)`"));
    try testing.expect(!contains(refused.stderr, "declares a function `index`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(source, after);
}

// MSG-B 2: after `import sort` the name `sort` is the module's, and the builtin `sort(mut values)` was refused as "this module declares no
// `sort`". The refusal says so, and `selka fix` removes the import that nothing else in the file uses.
test "CLI an import that hides the builtin sort is named in the refusal, and fix removes it when nothing else uses the module (MSG-B)" {
    const source =
        \\import sort
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut xs = [3, 1, 2]
        \\    sort(mut xs)
        \\    print(out, xs[0])
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    // The frame is pinned, and the names it offers come from the module by a rule (`interfaces_test.zig`), so a function added to `sort`
    // does not change this test: the first of them is an in-place `sort_` function, and `selka reference` is where the rest are.
    try testing.expect(contains(refused.stderr, "main.selka:6:5: error[E_UNKNOWN_SYMBOL]: this module declares no `sort`; `sort` here names the imported " ++
        "module `sort`, which hides the builtin `sort`: write a function of the module, such as `sort.sort_"));
    try testing.expect(contains(refused.stderr, "(...)` (`selka reference --query sort` lists them), or remove `import sort` to reach the builtin"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 1 edit in 1 file"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(!contains(after, "import sort"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("1\n", ran.stdout);
}

// MSG-B 3: a project's `options.selka` beside the entry loses to the standard module `options` and was never mentioned: `options.Options(...)`
// was "module `options` declares no `Options`" and nothing said why. The refusal says whose `options` it is, and `check` names each local
// file a standard module hides once, as `build` does, in the commands `packages build` runs too.
test "CLI a local file that a standard module hides is named by check, check-project and project-dependencies, and in the refusal (MSG-B)" {
    var project = try Project.init(&.{
        .{ .path = "ok.selka", .data = "import options\n\nfunc main() -> int:\n    return options.take_or(None, 7)\n" },
        .{ .path = "main.selka", .data = "import options\n\nfunc main(out: Stream) -> int:\n    const o = options.Options(verbose=True)\n    print(out, o.verbose)\n    return 0\n" },
        .{ .path = "options.selka", .data = "public record Options:\n    verbose: bool\n" },
    });
    defer project.deinit();
    const warning = "selka: local standard module 'options.selka' is ignored; pass --local-stdlib to prefer it";
    const refusal = "main.selka:4:15: error[E_UNKNOWN_SYMBOL]: module `options` declares no `Options`; `options` here is the standard module, so your `options.selka` is not used: rename it";
    const checked = try project.run("check", "ok.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(contains(checked.stderr, warning));
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, warning));
    try testing.expect(contains(refused.stderr, refusal));
    for ([_][]const u8{ "check-project", "project-dependencies" }) |command| {
        const other = try project.run(command, "main.selka", &.{});
        defer other.deinit();
        try testing.expectEqual(@as(u8, 1), other.status);
        try testing.expect(contains(other.stderr, warning));
        try testing.expect(contains(other.stderr, refusal));
    }
    // Machine-readable output stays clean, and a file named as the entry is the file, so it hides nothing.
    const json = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer json.deinit();
    try testing.expect(!contains(json.stderr, "selka: local standard module"));
    try testing.expect(contains(json.stderr, "`options` here is the standard module, so your `options.selka` is not used: rename it"));
    const itself = try project.run("check", "options.selka", &.{});
    defer itself.deinit();
    try testing.expectEqual(@as(u8, 0), itself.status);
    try testing.expect(!contains(itself.stderr, "is ignored"));
}

test "the removed contains method gets no repair where the swap of its operands is not certain, and a call on a non-collection is no removal (FR19)" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func names() -> set[str]:
        \\    return {"a"}
        \\
        \\
        \\func mark(mut seen: set[str], name: str) -> str:
        \\    return copy(name)
        \\
        \\
        \\func main() -> int:
        \\    mut seen: set[str] = {"a"}
        \\    if names().contains(mark(mut seen, "a")):
        \\        return 1
        \\    if seen.contains(mark(mut seen, "a")):
        \\        return 2
        \\    return 0
        \\
    }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "`names().contains(mark(mut seen, \"a\"))` was removed for sets; use `mark(mut seen, \"a\") in names()`"));
    try testing.expect(contains(refused.stderr, "was removed for sets; use `mark(mut seen, \"a\") in seen`"));
    const structured = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer structured.deinit();
    try testing.expect(!contains(structured.stderr, "\"fix\""));
}

test "a case arm that binds nothing of a payload that needs handling names both patterns and offers no repair (FR14)" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\enum N:
        \\    atom(x: Result[i64, str], y: i64)
        \\    blank
        \\
        \\
        \\func f(n: N) -> i64:
        \\    match n:
        \\        case blank:
        \\            return 0
        \\        case atom:
        \\            return 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "`case atom` names a case with the fields `x: Result[int, str]` and `y: int`, so the pattern must say " ++
        "what the arm does with them: `case atom(..):` drops them and `case atom(x, y):` binds them to use"));
    try testing.expect(!contains(refused.stderr, "\"fix\""));
}

test "CLI fix offers no edit for a try over an operator, and a try as an operand checks as written (F-3, TRY-2)" {
    const head =
        \\func read(text: str) -> int fails str:
        \\    if text == "":
        \\        fail "empty"
        \\    return len(text)
        \\
        \\
        \\func after_call(a: str, b: str) -> int fails str:
        \\
    ;
    const tail = "\n\n\nfunc main() -> int:\n    return 0\n";
    const refused = head ++ "    return try (read(b) + len(a))" ++ tail;
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = refused }, .{ .path = "operand.selka", .data = head ++ "    return max(len(a), 0) + try read(b)" ++ tail } });
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expect(contains(fixed.stdout, "E_TRY_POSITION") or contains(fixed.stderr, "E_TRY_POSITION"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(refused, after);
    const checked = try project.run("check", "operand.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix declares from where no caller keeps a returned parameter and copies where one does, in one round (F-8, F-15)" {
    const original = @embedFile("fixtures/fix-migration/return-param-callers.selka");
    const wanted = @embedFile("fixtures/fix-migration/return-param-callers.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqualStrings("Queued\nhttps://a\n", ran.stdout);
    // `ward` keeps `https_url`'s result, so the copy the fix wrote draws no `from` hint.
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stderr, "W_COPY_MOVE"));
}

/// F-27's function: it copies one field of each element of a plain list parameter and returns the copies.
const names_of_uses =
    \\import lists
    \\
    \\record Use:
    \\    name: str
    \\    line: int
    \\
    \\
    \\func names_of(uses: Use[]) -> str[]:
    \\    mut names: str[] = []
    \\    for use in uses:
    \\        if not lists.contains(names, use.name):
    \\            append(mut names, copy(use.name))
    \\    return names
    \\
    \\
;

test "check leaves out the own-parameter W_COPY_MOVE hint where a caller still needs the list it passes, and keeps it otherwise (F-27)" {
    var keeping = try Project.init(&.{.{ .path = "main.selka", .data = names_of_uses ++
        \\func main() -> int:
        \\    const uses = [Use(name="a", line=1), Use(name="a", line=2)]
        \\    const n = len(names_of(uses))
        \\    return n + len(uses)
        \\
    }});
    defer keeping.deinit();
    const kept = try keeping.run("check", "main.selka", &.{});
    defer kept.deinit();
    try testing.expectEqual(@as(u8, 0), kept.status);
    try testing.expect(!contains(kept.stderr, "W_COPY_MOVE"));
    var giving = try Project.init(&.{.{ .path = "main.selka", .data = names_of_uses ++
        \\func main() -> int:
        \\    const uses = [Use(name="a", line=1), Use(name="a", line=2)]
        \\    return len(names_of(uses))
        \\
    }});
    defer giving.deinit();
    const given = try giving.run("check", "main.selka", &.{});
    defer given.deinit();
    try testing.expectEqual(@as(u8, 0), given.status);
    try testing.expect(contains(given.stderr, "`for use in own uses` hands the elements over when `uses` is an owned local or an `own` parameter " ++
        "(each of its callers then gives its list with `own`)"));
}

test "check leaves out the from hint where a caller binds the result and then passes the record mut (F-24)" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\record Work:
        \\    lines: str[]
        \\    targets: str[]
        \\
        \\
        \\func target(work: Work) -> str:
        \\    return copy(work.targets[len(work.targets) - 1])
        \\
        \\
        \\func emit(mut work: Work, statement: str):
        \\    append(mut work.lines, copy(statement))
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut work = Work(lines=[], targets=["out"])
        \\    const into = target(work)
        \\    emit(mut work, "strings.append(mut " + into + ", 'x')")
        \\    print(out, work.lines[0])
        \\    return 0
        \\
    }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(!contains(checked.stderr, "W_COPY_MOVE"));
}

test "check keeps the W_COPY_MOVE hint of a function whose callers only read its result (F-8)" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func label(status: str) -> str:
        \\    if status == "":
        \\        return "none"
        \\    return copy(status)
        \\
        \\
        \\func main() -> int:
        \\    return len(label("Queued"))
        \\
    }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(contains(checked.stderr, "warning[W_COPY_MOVE]: every return of `label` copies a place of `status`"));
}

const generated_module =
    \\# GENERATED by gen.py from gen.view. Do not edit.
    \\import unused
    \\
    \\
    \\public func one() -> int:
    \\    return 1
    \\
;

const hand_module =
    \\import unused
    \\
    \\
    \\public func one() -> int:
    \\    return 1
    \\
;

const generated_project = [_]File{
    .{ .path = "main.selka", .data = "import hand\nimport gen\n\n\nfunc main(out: Stream) -> int:\n    print(out, hand.one(), gen.one())\n    return 0\n" },
    .{ .path = "hand.selka", .data = hand_module },
    .{ .path = "gen.selka", .data = generated_module },
    .{ .path = "unused.selka", .data = unused_module },
};

// spec-case: FIX-GENERATED-1
test "CLI fix leaves a file whose first line says it is generated alone, counts what it left, and repairs the file named (FR22)" {
    var project = try Project.init(&generated_project);
    defer project.deinit();
    const preview = try project.run("fix", ".", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix hand.selka: 1 edit (W_UNUSED_IMPORT)"));
    try testing.expect(!contains(preview.stdout, "gen.selka"));
    try testing.expect(contains(preview.stdout, "fix: left 1 fix in 1 generated file alone (the first line of each says `# generated by`"));
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed hand.selka: 1 edit (W_UNUSED_IMPORT)"));
    try testing.expect(!contains(fixed.stdout, "fixed gen.selka"));
    try testing.expect(contains(fixed.stdout, "fix: left 1 fix in 1 generated file alone"));
    // The warning left in the generated file is printed once, and the check's closing line (the command that is running, with the
    // directory it was given) is not passed on beside the run's own (FR52).
    try testing.expectEqualStrings(
        "gen.selka:2:8: warning[W_UNUSED_IMPORT]: import `unused` is never referenced in this module; remove it or use it\n  import unused\n         ^\n",
        fixed.stderr,
    );
    try expectFile(&project, "gen.selka", generated_module);
    const hand = try project.read("hand.selka");
    defer testing.allocator.free(hand);
    try testing.expect(!contains(hand, "import unused"));
    // The file named on the command line is repaired all the same, and says so as any other repair does.
    const named = try project.run("fix", "gen.selka", &.{"--warnings"});
    defer named.deinit();
    try testing.expectEqual(@as(u8, 0), named.status);
    try testing.expect(contains(named.stdout, "fixed gen.selka: 1 edit (W_UNUSED_IMPORT)"));
    try testing.expect(!contains(named.stdout, "generated file"));
    const generated = try project.read("gen.selka");
    defer testing.allocator.free(generated);
    try testing.expect(std.mem.startsWith(u8, generated, "# GENERATED by gen.py from gen.view. Do not edit.\n"));
    try testing.expect(!contains(generated, "import unused"));
}

// spec-case: FIX-GENERATED-1
test "CLI fix treats a lower-case marker the same and a comment that only mentions generated code as hand-written (FR22)" {
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = "import hand\nimport gen\n\n\nfunc main(out: Stream) -> int:\n    print(out, hand.one(), gen.one())\n    return 0\n" },
        .{ .path = "hand.selka", .data = "# Generated helpers, written by hand.\nimport unused\n\n\npublic func one() -> int:\n    return 1\n" },
        .{ .path = "gen.selka", .data = "# generated by protoc-gen-selka from field_mask.proto. Do not edit.\nimport unused\n\n\npublic func one() -> int:\n    return 1\n" },
        .{ .path = "unused.selka", .data = unused_module },
    });
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed hand.selka: 1 edit (W_UNUSED_IMPORT)"));
    try testing.expect(!contains(fixed.stdout, "fixed gen.selka"));
    try testing.expect(contains(fixed.stdout, "fix: left 1 fix in 1 generated file alone"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix rewrites every spelling W13 refuses that has a certain rewrite, and the program prints what it printed (W13-S2, W13-S5)" {
    const original = @embedFile("fixtures/fix-migration/method-forms.selka");
    const wanted = @embedFile("fixtures/fix-migration/method-forms.expected.selka");
    // What the corpus printed while its spellings still checked (main 8a72e05ab6, the last commit that accepted them).
    const printed = "a,b,c a,b,c   a,b,c 007\n['a,b,c'] a, b 7\n2 1 1\n2 2 4 4\nFalse False False True\n32 32\n" ++
        "False True True False\nSome(12) Some(1.5) Some(2.5)\n2 b'x,y' b'x,y ' b'x,y'\n1 1 1 1\n1 1 False False\nTrue False 1 1 1\n" ++
        "1 1 1\nSome(12) Some(1.5) Ok(4) [120, 44, 121, 32] 1\nOk('x,y ') 782c7920 32 32\n2 1 True True\nb'k,v' b'k,v ' b' k,v' 2\n" ++
        "None None Ok(3)\nOk(' k,v ') 206b2c7620\n3 True\n0 3\n3 5 4 9 4.0\nSome(41) Some(0.5)\n3.0 2.0 3.0 -2.0\nFalse False\n";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_METHOD_REMOVED]: `encode()` is a function now; write `strings.encode(s)`"));
    try testing.expect(contains(refused.stderr, "error[E_REMOVED_SPELLING]: `exists(fs, ...)` is a second spelling and was removed; " ++
        "write `fs.exists(\"no-such-file\")`"));
    try testing.expectEqual(@as(usize, 75), std.mem.count(u8, refused.stderr, "error[E_METHOD_REMOVED]"));
    try testing.expect(contains(refused.stderr, "error[E_REMOVED_SPELLING]: `math.round` is a second spelling and was removed; write `round(2.6)`; " ++
        "a result of zero keeps its sign, so `round(-0.4)` is `-0.0` where `math.round(-0.4)` was `0.0`"));
    try testing.expectEqual(@as(usize, 13), std.mem.count(u8, refused.stderr, "error[E_REMOVED_SPELLING]"));
    // A build refuses them too.
    const unbuilt = try project.run("run", "main.selka", &.{});
    defer unbuilt.deinit();
    try testing.expectEqual(@as(u8, 1), unbuilt.status);
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 93 edits in 1 file over 3 rounds"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(printed, ran.stdout);
    const clean = try project.run("check", "main.selka", &.{"--warnings"});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
    const again = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const formatted = try project.run("fmt", "main.selka", &.{});
    defer formatted.deinit();
    try testing.expectEqualStrings(wanted, formatted.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix leaves the W13 spellings whose rewrite is not certain, each refused with its reason (W13-S2, W13-S5)" {
    const original = @embedFile("fixtures/fix-migration/method-forms-uncertain.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    // Nothing is certain, so nothing is written, and the file is still refused.
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stdout, "nothing to fix"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(original, after);
    const warned = try project.run("check", "main.selka", &.{ "--warnings", "--diagnostics=json" });
    defer warned.deinit();
    try testing.expectEqual(@as(u8, 1), warned.status);
    try testing.expect(contains(fixed.stderr, "E_METHOD_REMOVED"));
    try testing.expectEqual(@as(usize, 4), std.mem.count(u8, warned.stderr, "\"code\":\"E_METHOD_REMOVED\""));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, warned.stderr, "\"code\":\"E_REMOVED_SPELLING\""));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, warned.stderr, "\"code\":\"E_INTERNAL_NAME\""));
    try testing.expect(!contains(warned.stderr, "\"fix\""));
    try testing.expect(contains(warned.stderr, "this unit declares or imports `parse_float`"));
    try testing.expect(contains(warned.stderr, "this file binds the name `hex`"));
    try testing.expect(contains(warned.stderr, "both operands are evaluated work"));
    try testing.expect(contains(warned.stderr, "its result is not compared with a literal"));
    try testing.expect(contains(warned.stderr, "an integer literal operand takes its type from the call"));
    try testing.expect(contains(warned.stderr, "`math.abs` fails on the most negative `int`"));
    // `strings.starts_with_at` stays (W13-Q3b): it answers where the bounded `starts_with` traps, so it is not refused.
    try testing.expect(!contains(warned.stderr, "starts_with_at"));
    try testing.expect(contains(warned.stderr, "`stop_control` is the standard library's own channel"));
}

// spec-case: FIX-MIGRATION-1
test "CLI fix rewrites the W13 shapes slice 5 made certain, and every rewrite on a buffer element, slice or call checks (W13-S5)" {
    const original = @embedFile("fixtures/fix-migration/method-forms-s5.selka");
    const wanted = @embedFile("fixtures/fix-migration/method-forms-s5.expected.selka");
    // What the corpus printed while its spellings still checked (main 8a72e05ab6).
    const printed = "a\nb a\t|b\n3 9 4\n5 b',b c,' 2\n1 1 2\n";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    // Two escaped joins and eight buffer reads are methods; three `math` calls are second spellings; each has its edit.
    try testing.expectEqual(@as(usize, 8), std.mem.count(u8, refused.stderr, "\"code\":\"E_METHOD_REMOVED\""));
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, refused.stderr, "\"code\":\"E_REMOVED_SPELLING\""));
    try testing.expectEqual(@as(usize, 11), std.mem.count(u8, refused.stderr, "\"fix\""));
    try testing.expect(contains(refused.stderr, "write `min(small, 3u8)`"));
    const fixed = try project.run("fix", "main.selka", &.{"--warnings"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 15 edits in 1 file over 2 rounds"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(printed, ran.stdout);
    const clean = try project.run("check", "main.selka", &.{"--warnings"});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
}

// A program that wrote `text.encode()` needed no import; `strings.encode(text)` needs `import strings`. Whatever the
// position of the qualified name, the refusal names the import and carries it as the repair (W13-S5).
test "CLI a standard module used without its import is refused with the import as its repair, in every position (W13-S5)" {
    const source =
        \\func width(b: strings.Builder) -> int:
        \\    return 0
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const a = strings.encode("x")
        \\    strings.encode("y")
        \\    print(out, len(a))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:1:15: error[E_MODULE_NOT_IMPORTED]: `strings` is a standard module that this file does not import; add `import strings`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.startsWith(u8, after, "import strings\n\nfunc width(b: strings.Builder) -> int:"));
    // With the type's import in place, the expression and the statement are refused the same way until it is.
    const body =
        \\import buffers
        \\
        \\func main(out: Stream) -> int:
        \\    const a = strings.encode("x")
        \\    hex.encode(a)
        \\    print(out, len(a), buffers.empty())
        \\    return 0
        \\
    ;
    var second = try Project.init(&.{.{ .path = "main.selka", .data = body }});
    defer second.deinit();
    const expression = try second.run("check", "main.selka", &.{});
    defer expression.deinit();
    try testing.expectEqual(@as(u8, 1), expression.status);
    try testing.expect(contains(expression.stderr, "main.selka:4:15: error[E_MODULE_NOT_IMPORTED]: `strings` is a standard module that this file does not import"));
    const repaired = try second.run("fix", "main.selka", &.{});
    defer repaired.deinit();
    try testing.expectEqual(@as(u8, 0), repaired.status);
    const whole = try second.read("main.selka");
    defer testing.allocator.free(whole);
    try testing.expect(contains(whole, "import buffers\nimport hex\nimport strings\n"));
}

// `bytes` is a type and a standard module: `bytes.parse_float(data)` without `import bytes` names the module's function,
// and once the import is there the type's `bytes.fromhex(text)` keeps working through the module (W13-S5).
test "CLI a bytes module call without its import gets the import, and bytes.fromhex still checks once it is there (W13-S5)" {
    const source =
        \\func main(out: Stream) -> int:
        \\    print(out, bytes.parse_float(b"1.5"), bytes.fromhex("41"))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:2:16: error[E_MODULE_NOT_IMPORTED]: `bytes` is a standard module that this file does not import; add `import bytes`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("Some(1.5) Ok(b'A')\n", ran.stdout);
}

// A module of the project is answered like a standard module: the file does not import it, and the import is the repair (FR32).
test "CLI a project module used without its import gets the import, in a call, a type and a nested path, and the file then checks (FR32)" {
    const util = "public func twice(n: int) -> int:\n    return n * 2\n\npublic record Row:\n    a: int\n";
    const calc = "public func f(n: int) -> int:\n    return n + 1\n";
    const source =
        \\func width(r: util.Row) -> int:
        \\    return r.a
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, util.twice(2), width(util.Row(a=3)))
        \\    print(out, shared.calc.f(1), calc.f(2))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = source }, .{ .path = "util.selka", .data = util }, .{ .path = "shared/calc.selka", .data = calc } });
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:1:15: error[E_MODULE_NOT_IMPORTED]: `util` is a module of this project that this file does not import; add `import util`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.startsWith(u8, after, "import shared.calc\nimport util\n\nfunc width(r: util.Row) -> int:"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("4 3\n2 3\n", ran.stdout);
}

test "CLI a project module without its import, in a file that imports others, gets the import, and a name with no module file keeps its message (FR32)" {
    const util = "public func twice(n: int) -> int:\n    return n * 2\n\npublic record Row:\n    a: int\n";
    const source =
        \\import strings
        \\
        \\func width(r: util.Row) -> int:
        \\    return r.a
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, strings.upper("a"), util.twice(2), width(util.Row(a=1)))
        \\    return 0
        \\
    ;
    const other = "func main(out: Stream) -> int:\n    print(out, nothing.twice(2))\n    return 0\n";
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = source }, .{ .path = "util.selka", .data = util }, .{ .path = "other.selka", .data = other } });
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, refused.stderr, "\"code\":\"E_MODULE_NOT_IMPORTED\""));
    try testing.expect(contains(refused.stderr, "`util` is a module of this project that this file does not import; add `import util`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.startsWith(u8, after, "import strings\nimport util\n\nfunc width"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqualStrings("A 4 1\n", ran.stdout);
    const kept = try project.run("check", "other.selka", &.{});
    defer kept.deinit();
    try testing.expectEqual(@as(u8, 1), kept.status);
    try testing.expect(contains(kept.stderr, "other.selka:2:16: error[E_UNKNOWN_TYPE]: `nothing` is not a name in scope here: it is no local, parameter, type or imported module, and no module file of this project has that name"));
}

// FR34 item 1: a method call on a Clock names `time.now(clock)` and its import, and `selka fix` writes both. A file that already imports
// `time` is told the function only, and one that imports it under another name keeps the plain advice.
test "CLI a method call on a Clock is told the standard module's function, and fix writes it with the import (FR34)" {
    const head = "func main(out: Stream, clock: Clock) -> int:\n    print(out, ";
    const without = head ++ "clock.now())\n    return 0\n";
    const imported = "import time\n\n" ++ head ++ "clock.monotonic())\n    return 0\n";
    const renamed = "import time as t\n\n" ++ head ++ "clock.monotonic())\n    return 0\n";
    var project = try Project.init(&.{ .{ .path = "without.selka", .data = without }, .{ .path = "imported.selka", .data = imported }, .{ .path = "renamed.selka", .data = renamed } });
    defer project.deinit();
    const plain = try project.run("check", "without.selka", &.{});
    defer plain.deinit();
    try testing.expectEqual(@as(u8, 1), plain.status);
    try testing.expect(contains(plain.stderr, "write the function form `time.now(clock)`, from the standard module `time`, and add `import time`"));
    const has_import = try project.run("check", "imported.selka", &.{});
    defer has_import.deinit();
    try testing.expect(contains(has_import.stderr, "write the function form `time.monotonic(clock)`, from the standard module `time`"));
    try testing.expect(!contains(has_import.stderr, "and add `import"));
    const aliased = try project.run("check", "renamed.selka", &.{});
    defer aliased.deinit();
    try testing.expect(contains(aliased.stderr, "no function `monotonic` is declared or in the prelude, so declare it first"));
    const fixed = try project.run("fix", "without.selka", &.{});
    defer fixed.deinit();
    const after = try project.read("without.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings("import time\n\n" ++ head ++ "time.now(clock))\n    return 0\n", after);
    const fixed_imported = try project.run("fix", "imported.selka", &.{});
    defer fixed_imported.deinit();
    const after_imported = try project.read("imported.selka");
    defer testing.allocator.free(after_imported);
    try testing.expectEqualStrings("import time\n\n" ++ head ++ "time.monotonic(clock))\n    return 0\n", after_imported);
}

// FR37: a method call on a Clock reached through a field names `time.now(ctx.clock)` with the receiver as written, and `selka fix`
// writes it with the import. An unknown method is told how the Clock is read and has no repair.
test "CLI a method call on a Clock reached through a field is told the module function with its receiver, and fix writes it (FR37)" {
    const record = "record Ctx:\n    clock: Clock\n\nfunc stamp(ctx: Ctx) -> int:\n    return ";
    const main = "\n\nfunc main(out: Stream, clock: Clock) -> int:\n    print(out, stamp(Ctx(clock=clock)) >= 0)\n    return 0\n";
    const without = record ++ "ctx.clock.monotonic()" ++ main;
    const imported = "import time\n\n" ++ record ++ "ctx.clock.monotonic()" ++ main;
    const unknown = record ++ "ctx.clock.tick()" ++ main;
    var project = try Project.init(&.{ .{ .path = "without.selka", .data = without }, .{ .path = "imported.selka", .data = imported }, .{ .path = "unknown.selka", .data = unknown } });
    defer project.deinit();
    const plain = try project.run("check", "without.selka", &.{});
    defer plain.deinit();
    try testing.expectEqual(@as(u8, 1), plain.status);
    try testing.expect(contains(plain.stderr, "error[E_COLLECTION_METHOD]: unknown method for a Clock receiver; a Clock has no methods; "));
    try testing.expect(contains(plain.stderr, "write the function form `time.monotonic(ctx.clock)`, from the standard module `time`, and add `import time`"));
    try testing.expect(contains(plain.stderr, "repairs 1 of these 1"));
    const told = try project.run("check", "unknown.selka", &.{});
    defer told.deinit();
    try testing.expect(contains(told.stderr, "a Clock has no methods; read it with time.now(ctx.clock), and add `import time`"));
    try testing.expect(!contains(told.stderr, "repairs"));
    const fixed = try project.run("fix", "without.selka", &.{});
    defer fixed.deinit();
    const after = try project.read("without.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings("import time\n\n" ++ record ++ "time.monotonic(ctx.clock)" ++ main, after);
    const fixed_imported = try project.run("fix", "imported.selka", &.{});
    defer fixed_imported.deinit();
    const after_imported = try project.read("imported.selka");
    defer testing.allocator.free(after_imported);
    try testing.expectEqualStrings("import time\n\n" ++ record ++ "time.monotonic(ctx.clock)" ++ main, after_imported);
    const ran = try project.run("run", "without.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("True\n", ran.stdout);
}

test "CLI fix rewrites every list exchange to its home, whatever the index, element or replacement (W13-S3)" {
    const original = @embedFile("fixtures/fix-migration/list-exchange.selka");
    const wanted = @embedFile("fixtures/fix-migration/list-exchange.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    // What the corpus printed while the method still checked (main 8a72e05ab6).
    const printed = "2 [1, 9, 3]\n3 1 [5, 9, 7]\n-1 5\na ['c', 'b']\n1 4\n[2] [[1], [3, 4]]\n";
    const warned = try project.run("check", "main.selka", &.{ "--warnings", "--diagnostics=json" });
    defer warned.deinit();
    try testing.expectEqual(@as(u8, 1), warned.status);
    // `lists.exchange` is the method's own operation, so each of the seven carries the edit: a `u8`, `u64` and `i8`
    // index, an `Ok(5)` the list types, a named text given `own`, a record and a list.
    try testing.expectEqual(@as(usize, 7), std.mem.count(u8, warned.stderr, "\"code\":\"E_METHOD_REMOVED\""));
    try testing.expectEqual(@as(usize, 7), std.mem.count(u8, warned.stderr, "\"fix\""));
    try testing.expect(contains(warned.stderr, "write `lists.exchange(mut names, 0, own name)`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 8 edits in 1 file over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(wanted, after);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(printed, ran.stdout);
    const clean = try project.run("check", "main.selka", &.{"--warnings"});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning["));
}

// spec-case: FIX-MIGRATION-1
test "CLI a W13 waiver excuses no refusal, fix rewrites the waived site too, and the standard library is refused nothing (W13-S5)" {
    const source =
        \\import strings
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    # lint: allow method-form reason="this line pins the method spelling"
        \\    const kept = "ab".encode()
        \\    print(out, len(kept), strings.upper("x"), "c".encode())
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, refused.stderr, "error[E_METHOD_REMOVED]"));
    try testing.expect(!contains(refused.stderr, "@stdlib/"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "const kept = strings.encode(\"ab\")"));
    try testing.expect(contains(after, "strings.encode(\"c\")"));
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix adds every missing standard-module import in one round, in the sorted block the formatter keeps (FR28)" {
    const original = @embedFile("fixtures/fix-migration/missing-imports.selka");
    const wanted = @embedFile("fixtures/fix-migration/missing-imports.expected.selka");
    // What the corpus prints with its imports in place: five modules were missing, each at a different slot of the block.
    const printed = "A [7, 2]\n6869\n2\n5.0\nTrue\nb'aGk='\n";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expectEqual(@as(usize, 5), std.mem.count(u8, refused.stderr, "\"code\":\"E_MODULE_NOT_IMPORTED\""));
    // Five imports insert at three points of the block (before `lists`, between `lists` and `strings`, after `strings`):
    // each point gets one edit, and the three go in together. They used to wait one round each.
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expect(contains(preview.stdout, "would fix main.selka: 3 edits (E_MODULE_NOT_IMPORTED)"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 3 edits in 1 file over 1 round"));
    try expectFile(&project, "main.selka", wanted);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings(printed, ran.stdout);
    // The block is where the formatter keeps it, and nothing is left to repair.
    const formatted = try project.run("fmt", "main.selka", &.{"--check"});
    defer formatted.deinit();
    try testing.expectEqual(@as(u8, 0), formatted.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes the imports of a file that has none as one sorted block in one round, however many it needs (FR28)" {
    const original =
        \\func shout(text: str) -> str:
        \\    return strings.upper(text)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut xs: int[] = [1, 2]
        \\    _ = lists.exchange(mut xs, 0, 7)
        \\    print(out, shout("a"), xs)
        \\    print(out, hex.encode(b"hi"))
        \\    print(out, bytes.find(b"abc", b"c"))
        \\    print(out, strings.lower("B"))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 1 edit in 1 file over 1 round"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.startsWith(u8, after, "import bytes\nimport hex\nimport lists\nimport strings\n\nfunc shout(text: str) -> str:\n"));
    const formatted = try project.run("fmt", "main.selka", &.{"--check"});
    defer formatted.deinit();
    try testing.expectEqual(@as(u8, 0), formatted.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix finds the import a refusal hid behind another one in the same statement, and none that a local or a member names (FR28)" {
    // The first refusal ends the statement's check, so `bytes` used to wait for a second round; `time` is a local here and
    // `stamp.json` a member, neither a module.
    const original =
        \\record Stamp:
        \\    value: int = 0
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const time = Stamp(value=3)
        \\    const stamp = Stamp(value=4)
        \\    print(out, hex.encode(b"hi"), time.value, bytes.find(b"abc", b"c"), stamp.json)
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, refused.stderr, "\"code\":\"E_MODULE_NOT_IMPORTED\""));
    try testing.expect(contains(refused.stderr, "add `import hex`"));
    try testing.expect(contains(refused.stderr, "add `import bytes`"));
    try testing.expect(!contains(refused.stderr, "add `import time`"));
    try testing.expect(!contains(refused.stderr, "add `import json`"));
}

// spec-case: FIX-MIGRATION-1
test "CLI the refusal of the bare open(fs, ...) spelling comes before the failure of a mode that is no literal, and fix rewrites it (FR28)" {
    const original =
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    const mode = "r"
        \\    with open(fs, "x.txt", mode) as f:
        \\        print(out, "open")
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    const spelling = std.mem.indexOf(u8, refused.stderr, "error[E_REMOVED_SPELLING]: `open(fs, ...)` is a second spelling and was removed; write `fs.open(\"x.txt\", mode)`") orelse return error.TestUnexpectedResult;
    const argument = std.mem.indexOf(u8, refused.stderr, "error[E_FILE_ARGUMENT]: open requires a literal mode") orelse return error.TestUnexpectedResult;
    try testing.expect(spelling < argument);
    // The rewrite is certain, so `fix` makes it and leaves the mode, which only the program can decide.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "with fs.open(\"x.txt\", mode) as f:"));
    try testing.expect(!contains(after, "open(fs,"));
    try testing.expect(contains(fixed.stderr, "E_FILE_ARGUMENT"));
}

// FR35: the message of an unused Stream parameter of `main` says to delete it, and the diagnostic carries that deletion, so the check's
// closing line names `selka fix` and `fix` leaves a file that checks. A `main` that is called, or whose parameter has a comment beside it,
// keeps the message and no edit.
test "CLI fix deletes the unused Stream parameters of main, comma and all, and leaves a main that is called alone (FR35)" {
    const only = "func main(out: Stream) -> int:\n    return 0\n";
    const both = "func main(\n    args: str[],\n    out: Stream,\n    err: Stream,\n) -> int:\n    return len(args)\n";
    const called = "func helper(out: Stream) -> int:\n    print(out, \"x\")\n    return main(out)\n\nfunc main(out: Stream) -> int:\n    return 0\n";
    var project = try Project.init(&.{ .{ .path = "only.selka", .data = only }, .{ .path = "both.selka", .data = both }, .{ .path = "called.selka", .data = called } });
    defer project.deinit();
    const refused = try project.run("check", "only.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "delete the parameter (an entry Stream parameter must be named `out` or `err`, so it cannot be renamed `_out`)"));
    try testing.expect(contains(refused.stderr, "repairs 1 of these 1"));
    const fixed = try project.run("fix", "only.selka", &.{});
    defer fixed.deinit();
    const after = try project.read("only.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings("func main() -> int:\n    return 0\n", after);
    const clean = try project.run("check", "only.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    const fixed_both = try project.run("fix", "both.selka", &.{});
    defer fixed_both.deinit();
    const after_both = try project.read("both.selka");
    defer testing.allocator.free(after_both);
    try testing.expectEqualStrings("func main(\n    args: str[],\n) -> int:\n    return len(args)\n", after_both);
    const clean_both = try project.run("check", "both.selka", &.{});
    defer clean_both.deinit();
    try testing.expectEqual(@as(u8, 0), clean_both.status);
    const kept = try project.run("check", "called.selka", &.{});
    defer kept.deinit();
    try testing.expect(contains(kept.stderr, "delete the parameter"));
    try testing.expect(!contains(kept.stderr, "selka fix"));
    const left = try project.run("fix", "called.selka", &.{});
    defer left.deinit();
    const after_called = try project.read("called.selka");
    defer testing.allocator.free(after_called);
    try testing.expectEqualStrings(called, after_called);
}

// spec-case: FR42
test "CLI fix leaves `_ = own tx.undo` of a @linear owner alone, and the check after it still says why (FR42)" {
    const discard = "@linear\nrecord Tx:\n    undo: int[]\n    weight: int\n\nfunc rollback(own tx: Tx):\n    _ = own tx.undo\n\n" ++
        "func main() -> int:\n    rollback(Tx(undo=[], weight=0))\n    return 0\n";
    const plain = "record Tx:\n    undo: int[]\n    weight: int\n\nfunc rollback(own tx: Tx):\n    _ = own tx.undo\n\n" ++
        "func main() -> int:\n    rollback(Tx(undo=[], weight=0))\n    return 0\n";
    var project = try Project.init(&.{ .{ .path = "linear.selka", .data = discard }, .{ .path = "plain.selka", .data = plain } });
    defer project.deinit();
    // The refusal names the owner, says removing `own` leaves it unconsumed, and offers no repair.
    const refused = try project.run("check", "linear.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_OWN_MARKER]: `own tx.undo` gives `tx.undo`, but this position only reads it, so it does not end the `@linear` owner `tx`"));
    try testing.expect(contains(refused.stderr, "removing `own` would leave `tx` unconsumed; take the field where its value is kept (`const kept = own tx.undo`"));
    try testing.expect(!contains(refused.stderr, "selka fix"));
    // `fix` writes nothing, so the program is refused for the same reason after it, never for an unconsumed owner.
    const fixed = try project.run("fix", "linear.selka", &.{});
    defer fixed.deinit();
    const after = try project.read("linear.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(discard, after);
    const again = try project.run("check", "linear.selka", &.{});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 1), again.status);
    try testing.expect(contains(again.stderr, "error[E_OWN_MARKER]"));
    try testing.expect(!contains(again.stderr, "E_LINEAR_UNCONSUMED"));
    // The same program without `@linear` keeps its message and its repair: the discard reads, and `own` goes.
    const old = try project.run("check", "plain.selka", &.{});
    defer old.deinit();
    try testing.expect(contains(old.stderr, "`own tx.undo` gives `tx.undo`, but this position only reads it; remove `own`"));
    const removed = try project.run("fix", "plain.selka", &.{});
    defer removed.deinit();
    const without = try project.read("plain.selka");
    defer testing.allocator.free(without);
    try testing.expectEqualStrings("record Tx:\n    undo: int[]\n    weight: int\n\nfunc rollback(own tx: Tx):\n    _ = tx.undo\n\n" ++
        "func main() -> int:\n    rollback(Tx(undo=[], weight=0))\n    return 0\n", without);
}

/// A program whose call needs its `mut` marker (an error, repaired by `selka fix`) and whose two files each import a module they
/// never use (a warning with a repair, in each file); the warnings show only once the error is repaired.
const errors_only_files = [_]File{
    .{ .path = "main.selka", .data = "import helpers\nimport unused\n\n\nfunc main() -> int:\n    mut xs: int[] = []\n    helpers.grow(xs)\n    return len(xs)\n" },
    .{ .path = "helpers.selka", .data = module_helpers },
    .{ .path = "unused.selka", .data = unused_module },
};

/// The files of `errors_only_files` as `project` holds them, one after the other.
fn errorsOnlyTree(project: *const Project) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(testing.allocator);
    for (errors_only_files) |file| {
        const text = try project.read(file.path);
        defer testing.allocator.free(text);
        try out.print(testing.allocator, "== {s}\n{s}", .{ file.path, text });
    }
    return out.toOwnedSlice(testing.allocator);
}

/// Require `args` run on `target` to find nothing to do, with `left` as the lines after "nothing to fix".
fn expectNothing(project: *const Project, target: []const u8, args: []const []const u8, left: []const u8) !void {
    const run = try project.run("fix", target, args);
    defer run.deinit();
    const wanted = try std.mem.concat(testing.allocator, u8, &.{ "fix: nothing to fix\n", left });
    defer testing.allocator.free(wanted);
    try testing.expectEqual(@as(u8, 0), run.status);
    try testing.expectEqualStrings(wanted, run.stdout);
}

// spec-case: FIX-FILE-2
test "CLI fix of a file repairs its errors only and names the warnings it left, and --warnings repairs them as a directory does" {
    var project = try Project.init(&errors_only_files);
    defer project.deinit();
    // The command is named with the path the run was given, and these tests give absolute paths.
    const left = try std.fmt.allocPrint(testing.allocator, "fix: left 2 warnings with a repair alone; `selka fix {s}/main.selka --warnings` repairs them too\n", .{project.root});
    defer testing.allocator.free(left);
    // `--check` lists what the run would apply, and writes nothing.
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expectEqualStrings("would fix main.selka: 1 edit (E_MUTATION_MARKER)\nfix --check: 1 edit in 1 file would change\n", preview.stdout);
    try expectFile(&project, "main.selka", errors_only_files[0].data);
    // The run applies the error's repair alone. The warnings it uncovers keep their code: the check that ends the run prints them,
    // and the run's own last line says how many it left and the command. The check's own closing line, which names the same
    // command with the absolute path the run gave it, is not passed on (FR52): standard error is the two warnings and nothing more.
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const fixed_text = try std.mem.concat(testing.allocator, u8, &.{ "fixed main.selka: 1 edit (E_MUTATION_MARKER)\nfix: 1 edit in 1 file over 1 round\n", left });
    defer testing.allocator.free(fixed_text);
    try testing.expectEqualStrings(fixed_text, fixed.stdout);
    try testing.expectEqualStrings(
        "main.selka:2:8: warning[W_UNUSED_IMPORT]: import `unused` is never referenced in this module; remove it or use it\n  import unused\n         ^\n" ++
            "helpers.selka:1:8: warning[W_UNUSED_IMPORT]: import `unused` is never referenced in this module; remove it or use it\n  import unused\n         ^\n",
        fixed.stderr,
    );
    try expectFile(&project, "main.selka", "import helpers\nimport unused\n\n\nfunc main() -> int:\n    mut xs: int[] = []\n    helpers.grow(mut xs)\n    return len(xs)\n");
    try expectFile(&project, "helpers.selka", module_helpers);
    // A second run of each finds nothing to apply, and a plain one still says what it left.
    try expectNothing(&project, "main.selka", &.{"--check"}, left);
    try expectNothing(&project, "main.selka", &.{}, left);
    // `--warnings` applies the warnings' repairs, and `--check --warnings` lists them first.
    const listed = try project.run("fix", "main.selka", &.{ "--check", "--warnings" });
    defer listed.deinit();
    try testing.expectEqual(@as(u8, 1), listed.status);
    try testing.expectEqualStrings("would fix helpers.selka: 1 edit (W_UNUSED_IMPORT)\nwould fix main.selka: 1 edit (W_UNUSED_IMPORT)\nfix --check: 2 edits in 2 files would change\n", listed.stdout);
    const warned = try project.run("fix", "main.selka", &.{"--warnings"});
    defer warned.deinit();
    try testing.expectEqual(@as(u8, 0), warned.status);
    try testing.expectEqualStrings("fixed helpers.selka: 1 edit (W_UNUSED_IMPORT)\nfixed main.selka: 1 edit (W_UNUSED_IMPORT)\nfix: 2 edits in 2 files over 1 round\n", warned.stdout);
    try expectNothing(&project, "main.selka", &.{ "--check", "--warnings" }, "");
    try expectNothing(&project, "main.selka", &.{"--warnings"}, "");
    try expectNothing(&project, "main.selka", &.{"--check"}, "");
    try expectNothing(&project, "main.selka", &.{}, "");
    const stepwise = try errorsOnlyTree(&project);
    defer testing.allocator.free(stepwise);
    // One `--warnings` run writes the same tree, and so does a directory run, with or without the flag, which prints the same.
    var at_once = try Project.init(&errors_only_files);
    defer at_once.deinit();
    const once = try at_once.run("fix", "main.selka", &.{"--warnings"});
    defer once.deinit();
    try testing.expectEqual(@as(u8, 0), once.status);
    const once_tree = try errorsOnlyTree(&at_once);
    defer testing.allocator.free(once_tree);
    try testing.expectEqualStrings(stepwise, once_tree);
    var directory = try Project.init(&errors_only_files);
    defer directory.deinit();
    const all = try directory.run("fix", ".", &.{});
    defer all.deinit();
    try testing.expectEqual(@as(u8, 0), all.status);
    const directory_tree = try errorsOnlyTree(&directory);
    defer testing.allocator.free(directory_tree);
    try testing.expectEqualStrings(stepwise, directory_tree);
    var flagged = try Project.init(&errors_only_files);
    defer flagged.deinit();
    const same = try flagged.run("fix", ".", &.{"--warnings"});
    defer same.deinit();
    try testing.expectEqualStrings(all.stdout, same.stdout);
    try testing.expectEqualStrings(all.stderr, same.stderr);
    const flagged_tree = try errorsOnlyTree(&flagged);
    defer testing.allocator.free(flagged_tree);
    try testing.expectEqualStrings(stepwise, flagged_tree);
}

// spec-case: FIX-FILE-2
test "CLI fix of a file in a project that denies warnings still repairs errors only, and the end line goes to standard output" {
    var project = try Project.init(&.{
        .{ .path = "selka.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" },
        errors_only_files[0],
        errors_only_files[1],
        errors_only_files[2],
    });
    defer project.deinit();
    // The warnings fail the check but keep their severity, so the run leaves them and the status says the check still fails.
    const fixed = try project.run("fix", "main.selka", &.{ "--diagnostics=json", "--report" });
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const wanted = try std.fmt.allocPrint(testing.allocator, "fixed main.selka: 1 edit (E_MUTATION_MARKER)\nfix: 1 edit in 1 file over 1 round\n" ++
        "fix: left 2 warnings with a repair alone; `selka fix {s}/main.selka --warnings` repairs them too\n" ++
        "fix report: 1 round with edits, 0 directory checks, 3 entry checks, 0 example checks\n", .{project.root});
    defer testing.allocator.free(wanted);
    try testing.expectEqualStrings(wanted, fixed.stdout);
    try testing.expect(contains(fixed.stderr, "\"code\":\"W_UNUSED_IMPORT\",\"severity\":\"warning\""));
    try testing.expect(!contains(fixed.stderr, "fix: left"));
    try testing.expect(!contains(fixed.stderr, "repairs"));
    const cleared = try project.run("fix", "main.selka", &.{"--warnings"});
    defer cleared.deinit();
    try testing.expectEqual(@as(u8, 0), cleared.status);
    try testing.expectEqualStrings("fixed helpers.selka: 1 edit (W_UNUSED_IMPORT)\nfixed main.selka: 1 edit (W_UNUSED_IMPORT)\nfix: 2 edits in 2 files over 1 round\n", cleared.stdout);
}

// spec-case: FIX-FILE-2
test "CLI fix of a module repairs the errors in that file only, and counts the warnings in it that --warnings repairs" {
    var project = try Project.init(&.{
        .{ .path = "user.selka", .data = module_user },
        .{ .path = "helpers.selka", .data = module_helpers },
        .{ .path = "unused.selka", .data = unused_module },
    });
    defer project.deinit();
    // The warning in `helpers.selka` is not `user.selka`'s: neither run of `user.selka` applies it, and only the one `--warnings` would apply
    // is counted, so the plain run says nothing of it and no longer names an error-free repair as left in an import.
    const fixed = try project.run("fix", "user.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed user.selka: 2 edits (E_MUTATION_MARKER)\nfix: 2 edits in 1 file over 1 round\n", fixed.stdout);
    try expectFile(&project, "helpers.selka", module_helpers);
    // The warning in the file named is counted: the plain run leaves it, says so, and `--warnings` repairs it.
    const left = try std.fmt.allocPrint(testing.allocator, "fix: left 1 warning with a repair alone; `selka fix {s}/helpers.selka --warnings` repairs it too\n", .{project.root});
    defer testing.allocator.free(left);
    try expectNothing(&project, "helpers.selka", &.{"--check"}, left);
    try expectNothing(&project, "helpers.selka", &.{}, left);
    const warned = try project.run("fix", "helpers.selka", &.{"--warnings"});
    defer warned.deinit();
    try testing.expectEqual(@as(u8, 0), warned.status);
    try testing.expectEqualStrings("fixed helpers.selka: 1 edit (W_UNUSED_IMPORT)\nfix: 1 edit in 1 file over 1 round\n", warned.stdout);
    try expectNothing(&project, "helpers.selka", &.{}, "");
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes a legacy postfix try in a call's argument as a prefix try in place, and leaves a prefix one there (TRYARG)" {
    const source =
        \\func check(n: int) -> int fails str:
        \\    if n > 1:
        \\        fail "too big"
        \\    return n
        \\
        \\
        \\func twice(n: int) -> int:
        \\    return n * 2
        \\
        \\
        \\func run(n: int) -> int fails str:
        \\    return twice(check(n)?) + twice(try check(n))
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, run(1), run(2))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    return twice(try check(n)) + twice(try check(n))\n"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("Ok(4) Err('too big')\n", ran.stdout);
}

// spec-case: FR45
test "CLI fix directory ignores the match bindings nothing reads, with `_` or `field=_`, and the program prints what it printed (FR45)" {
    const before_text =
        \\enum Json:
        \\    number(n: int, lit: str)
        \\    text(value: str)
        \\    pair(left: int, right: int)
        \\
        \\result Read:
        \\    ok: int,
        \\    err: int
        \\
        \\func score(j: Json) -> int:
        \\    match j:
        \\        case number(n, lit):
        \\            return n
        \\        case text(value):
        \\            return 7
        \\        case pair(left, right):
        \\            return left
        \\
        \\func read(r: Read) -> int:
        \\    match r:
        \\        case ok(v):
        \\            return 1
        \\        case err(code):
        \\            return code
        \\
        \\func found(v: int?) -> int:
        \\    if v is Some(x):
        \\        return 1
        \\    return 0
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, score(Json.number(n=4, lit="four")) + score(Json.text(value="t")) + score(Json.pair(left=5, right=6)))
        \\    print(out, read(Read.ok(1)) + read(Read.err(5)))
        \\    print(out, found(Some(3)) + found(None))
        \\    return 0
        \\
    ;
    const after_text =
        \\enum Json:
        \\    number(n: int, lit: str)
        \\    text(value: str)
        \\    pair(left: int, right: int)
        \\
        \\result Read:
        \\    ok: int,
        \\    err: int
        \\
        \\func score(j: Json) -> int:
        \\    match j:
        \\        case number(n, lit=_):
        \\            return n
        \\        case text(value=_):
        \\            return 7
        \\        case pair(left, right=_):
        \\            return left
        \\
        \\func read(r: Read) -> int:
        \\    match r:
        \\        case ok(_):
        \\            return 1
        \\        case err(code):
        \\            return code
        \\
        \\func found(v: int?) -> int:
        \\    if v is Some(_):
        \\        return 1
        \\    return 0
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, score(Json.number(n=4, lit="four")) + score(Json.text(value="t")) + score(Json.pair(left=5, right=6)))
        \\    print(out, read(Read.ok(1)) + read(Read.err(5)))
        \\    print(out, found(Some(3)) + found(None))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = before_text }});
    defer project.deinit();
    // The warning says what to write in the place of each name, and its repair is counted.
    const warned = try project.run("check", "main.selka", &.{});
    defer warned.deinit();
    try testing.expectEqual(@as(u8, 0), warned.status);
    try testing.expect(contains(warned.stderr, "main.selka:12:24: warning[W_UNUSED_BINDING]: binding `lit` is never read; write `lit=_` in its place to ignore this field"));
    try testing.expect(contains(warned.stderr, "main.selka:21:17: warning[W_UNUSED_BINDING]: binding `v` is never read; write `_` in its place to ignore the payload"));
    try testing.expect(contains(warned.stderr, "main.selka:27:18: warning[W_UNUSED_BINDING]: binding `x` is never read; write `_` in its place to ignore the payload"));
    try testing.expect(contains(warned.stderr, "repairs 5 of these 5"));
    const before = try project.run("run", "main.selka", &.{});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 0), before.status);
    try testing.expectEqualStrings("16\n6\n1\n", before.stdout);
    // A file run leaves the warning's repair alone; the directory run applies it.
    const kept = try project.run("fix", "main.selka", &.{});
    defer kept.deinit();
    try expectFile(&project, "main.selka", before_text);
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 5 edits (W_UNUSED_BINDING)"));
    try expectFile(&project, "main.selka", after_text);
    // The repaired program checks with no warning, prints what it printed, and a second run finds nothing.
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning"));
    const after = try project.run("run", "main.selka", &.{});
    defer after.deinit();
    try testing.expectEqualStrings(before.stdout, after.stdout);
    try expectNothing(&project, ".", &.{}, "");
}

// spec-case: FIX-MIGRATION-1
test "CLI fix directory leaves the labels of a nested pattern alone, settles in one round, and the program prints what it printed (FR49)" {
    const before_text =
        \\enum Item:
        \\    item(value: int, note: str)
        \\    empty
        \\
        \\
        \\func first(xs: Item[]) -> Item?:
        \\    if len(xs) == 0:
        \\        return None
        \\    return Some(xs[0])
        \\
        \\
        \\func value_of(xs: Item[]) -> int:
        \\    match first(xs):
        \\        case Some(item(value=value, note=note)):
        \\            return value + len(note)
        \\        case Some(empty):
        \\            return 0
        \\        case None:
        \\            return -1
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, value_of([Item.item(value=3, note="ab")]))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = before_text }});
    defer project.deinit();
    // The one error is the borrow of `first`; the nested labels stay, for the checker refuses `case Some(item(value, note))`.
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_BORROW_UNDECLARED]"));
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.selka: 1 edit (E_BORROW_UNDECLARED)"));
    try testing.expect(contains(fixed.stdout, "fix: 1 edit in 1 file over 1 round"));
    const text = try project.read("main.selka");
    defer testing.allocator.free(text);
    try testing.expect(contains(text, "func first(xs: Item[]) -> Item? from xs:"));
    try testing.expect(contains(text, "case Some(item(value=value, note=note)):"));
    // The repaired program checks with no warning, prints what the labels say, and a second run finds nothing.
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(!contains(clean.stderr, "warning"));
    const after = try project.run("run", "main.selka", &.{});
    defer after.deinit();
    try testing.expectEqual(@as(u8, 0), after.status);
    try testing.expectEqualStrings("5\n", after.stdout);
    try expectNothing(&project, ".", &.{}, "");
}

// spec-case: FIX-MIGRATION-1
test "CLI fix deletes a trailing return or fail that follows a statement that always leaves, and the program prints the same (FIXUNREACH)" {
    const original =
        \\enum Shape:
        \\    circle(r: int)
        \\    square(s: int)
        \\
        \\
        \\func area(s: Shape) -> int:
        \\    match s:
        \\        case circle(r=radius):
        \\            return 3 * radius * radius
        \\        case square(s=side):
        \\            return side * side
        \\    return 0
        \\
        \\
        \\func sign(n: int) -> int:
        \\    if n > 0:
        \\        return 1
        \\    elif n < 0:
        \\        return 0 - 1
        \\    else:
        \\        return 0
        \\    return 99  # the fallback never ran
        \\
        \\
        \\func check(n: int) -> int fails str:
        \\    if n > 3:
        \\        fail "big"
        \\    return n
        \\    fail "never"
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, area(Shape.circle(r=2)), area(Shape.square(s=3)), sign(5), sign(0 - 5), sign(0), check(2), check(5))
        \\    return 0
        \\
    ;
    const wanted =
        \\enum Shape:
        \\    circle(r: int)
        \\    square(s: int)
        \\
        \\
        \\func area(s: Shape) -> int:
        \\    match s:
        \\        case circle(r=radius):
        \\            return 3 * radius * radius
        \\        case square(s=side):
        \\            return side * side
        \\
        \\
        \\func sign(n: int) -> int:
        \\    if n > 0:
        \\        return 1
        \\    elif n < 0:
        \\        return 0 - 1
        \\    else:
        \\        return 0
        \\
        \\
        \\func check(n: int) -> int fails str:
        \\    if n > 3:
        \\        fail "big"
        \\    return n
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, area(Shape.circle(r=2)), area(Shape.square(s=3)), sign(5), sign(0 - 5), sign(0), check(2), check(5))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expect(refused.status != 0);
    try testing.expect(contains(refused.stderr, "every arm of the `match` at line 7 returns, so this statement cannot run"));
    try testing.expect(contains(refused.stderr, "every branch of the `if` at line 16 returns, so this statement cannot run"));
    try testing.expect(contains(refused.stderr, "main.selka` repairs 3 of these 3"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed main.selka: 3 edits (E_UNREACHABLE)\nfix: 3 edits in 1 file over 1 round\n", fixed.stdout);
    try expectFile(&project, "main.selka", wanted);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("12 9 1 -1 0 Ok(2) Err('big')\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes parentheses for a line continued after an operator or a backslash, one statement at a time" {
    const original = @embedFile("fixtures/fix-migration/line-continuation.selka");
    const wanted = @embedFile("fixtures/fix-migration/line-continuation.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:11:21: error[E_TOKEN]: a backslash does not continue a line: an expression continues on the next line " ++
        "only inside parentheses, so write `(a +` ... `b)` and no backslash"));
    try testing.expect(contains(refused.stderr, "main.selka` repairs 1 of these 1"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 12 edits in 1 file over 5 rounds\n"));
    try expectFile(&project, "main.selka", wanted);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("11\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes a braced Unicode escape of one to four digits as backslash u and four digits, once per round" {
    const original = @embedFile("fixtures/fix-migration/unicode-escape-braces.selka");
    const wanted = @embedFile("fixtures/fix-migration/unicode-escape-braces.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:4:16: error[E_BYTE_ESCAPE]: a Unicode escape has no braces: write `\\u` and exactly four hexadecimal digits, " ++
        "as in `\\u00e9`, or `\\U` and exactly eight, as in `\\U0001f600`, for a character above U+FFFF"));
    try testing.expect(contains(refused.stderr, "main.selka` repairs 1 of these 1"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(contains(fixed.stdout, "fix: 3 edits in 1 file over 3 rounds\n"));
    try expectFile(&project, "main.selka", wanted);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("\xef\xbf\xbd \xc3\xa9 A\n", ran.stdout);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix writes a Python conversion in a format string hole and a text times an integer as the calls they stand for" {
    const original = @embedFile("fixtures/fix-migration/python-spellings.selka");
    const expected = @embedFile("fixtures/fix-migration/python-spellings.expected.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    // The check refuses the first spelling (a parse error stops it before the second), and `fix` repairs both over two rounds.
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_TOKEN]"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try expectFile(&project, "main.selka", expected);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqualStrings("'ab' twice    7 9\n=== end\n", ran.stdout);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: NARROW-OWN
test "CLI fix writes `own found` for a bare read of a local narrowed to Some, and `copy(found)` for a plain parameter's (NARROW-OWN)" {
    const head = "record Cmd:\n    name: str\n\n\nrecord Inv:\n    db: str?\n    cmd: Cmd\n\n\n";
    const local = head ++ "func pick(name: str) -> Inv fails str:\n    mut found: Cmd? = None\n    if name == \"a\":\n" ++
        "        found = Some(Cmd(name=\"a\"))\n    if found is None:\n        fail \"unknown\"\n    return Inv(db=None, cmd=found)\n";
    const parameter = head ++ "func pack(found: Cmd?) -> Inv fails str:\n    if found is None:\n        fail \"none\"\n" ++
        "    return Inv(db=None, cmd=own found)\n";
    var project = try Project.init(&.{ .{ .path = "local.selka", .data = local }, .{ .path = "parameter.selka", .data = parameter } });
    defer project.deinit();
    const refused = try project.run("check", "local.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "write `own found` to give it, or `copy(found)` to keep both"));
    const fixed = try project.run("fix", "local.selka", &.{});
    defer fixed.deinit();
    const after = try project.read("local.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    return Inv(db=None, cmd=own found)\n"));
    const again = try project.run("check", "local.selka", &.{});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    // A plain parameter only lends: the refusal names it, and the repair writes the copy instead of only removing `own`.
    const lent = try project.run("check", "parameter.selka", &.{});
    defer lent.deinit();
    try testing.expect(contains(lent.stderr, "`own found` cannot give the plain parameter `found`, which only lends it"));
    const copied = try project.run("fix", "parameter.selka", &.{});
    defer copied.deinit();
    const written = try project.read("parameter.selka");
    defer testing.allocator.free(written);
    try testing.expect(contains(written, "    return Inv(db=None, cmd=copy(found))\n"));
    const checks = try project.run("check", "parameter.selka", &.{});
    defer checks.deinit();
    try testing.expectEqual(@as(u8, 0), checks.status);
}

// migrate-embedded: skip intentional several-paths program that omits the `mut` its callee declares
const unmarked_program =
    \\func bump(mut xs: int[]) -> Unit:
    \\    append(mut xs, 1)
    \\
    \\
    \\func main() -> int:
    \\    mut xs: int[] = []
    \\    bump(xs)
    \\    return len(xs)
    \\
;
const marked_program =
    \\func bump(mut xs: int[]) -> Unit:
    \\    append(mut xs, 1)
    \\
    \\
    \\func main() -> int:
    \\    mut xs: int[] = []
    \\    bump(mut xs)
    \\    return len(xs)
    \\
;
// migrate-embedded: skip intentional several-paths module whose helper call omits the `mut` its callee declares
const unmarked_module =
    \\func bump(mut xs: int[]) -> Unit:
    \\    append(mut xs, 1)
    \\
    \\
    \\public func grow(mut xs: int[]) -> Unit:
    \\    bump(xs)
    \\
;
// migrate-embedded: skip intentional several-paths program that omits the `mut` its imported callee declares
const unmarked_importer =
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    mut xs: int[] = []
    \\    lib.grow(xs)
    \\    return len(xs)
    \\
;
const marker_edit = "(E_MUTATION_MARKER)\n";

// spec-case: FIX-FILE-2
test "CLI fix of two programs of one project repairs their shared module once, and counts it once under --check" {
    var project = try Project.init(&.{
        .{ .path = "lib.selka", .data = unmarked_module },
        .{ .path = "main.selka", .data = unmarked_importer },
        .{ .path = "other.selka", .data = unmarked_importer },
    });
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{ "other.selka", "--check" });
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expectEqualStrings("would fix lib.selka: 1 edit " ++ marker_edit ++ "would fix main.selka: 1 edit " ++ marker_edit ++
        "would fix other.selka: 1 edit " ++ marker_edit ++ "fix --check: 3 edits in 3 files would change\n", preview.stdout);
    try expectFile(&project, "lib.selka", unmarked_module);
    // The first program repairs the module it imports, and the second finds it repaired.
    const fixed = try project.run("fix", "main.selka", &.{"other.selka"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed lib.selka: 1 edit " ++ marker_edit ++ "fixed main.selka: 1 edit " ++ marker_edit ++
        "fixed other.selka: 1 edit " ++ marker_edit ++ "fix: 3 edits in 3 files over 2 rounds\n", fixed.stdout);
    try expectFile(&project, "lib.selka", "func bump(mut xs: int[]) -> Unit:\n    append(mut xs, 1)\n\n\npublic func grow(mut xs: int[]) -> Unit:\n    bump(mut xs)\n");
    try expectNothing(&project, "main.selka", &.{"other.selka"}, "");
}

// spec-case: FIX-FILE-2
test "CLI fix of two unrelated files repairs each in the order written, and one --report line counts the checks of both" {
    var project = try Project.init(&.{ .{ .path = "a.selka", .data = unmarked_program }, .{ .path = "b.selka", .data = unmarked_program } });
    defer project.deinit();
    const fixed = try project.run("fix", "b.selka", &.{ "a.selka", "--report" });
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expect(std.mem.startsWith(u8, fixed.stdout, "fixed a.selka: 1 edit " ++ marker_edit ++ "fixed b.selka: 1 edit " ++ marker_edit ++ "fix: 2 edits in 2 files over 2 rounds\n"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, fixed.stdout, "fix report:"));
    try expectFile(&project, "a.selka", marked_program);
    try expectFile(&project, "b.selka", marked_program);
}

// spec-case: FIX-FILE-2
test "CLI fix of a file and a directory repairs the file as a file and the directory as a directory" {
    var project = try Project.init(&.{
        .{ .path = "a.selka", .data = unmarked_program },
        .{ .path = "sub/x.selka", .data = unmarked_program },
        .{ .path = "sub/y.selka", .data = unmarked_program },
    });
    defer project.deinit();
    const fixed = try project.run("fix", "a.selka", &.{"sub"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed a.selka: 1 edit " ++ marker_edit ++ "fixed sub/x.selka: 1 edit " ++ marker_edit ++
        "fixed sub/y.selka: 1 edit " ++ marker_edit ++ "fix: 3 edits in 3 files over 2 rounds\n", fixed.stdout);
    try expectFile(&project, "sub/y.selka", marked_program);
}

// spec-case: FIX-FILE-2
test "CLI fix with a path that cannot be used names it and repairs nothing, whichever place it is written in" {
    var project = try Project.init(&.{ .{ .path = "a.selka", .data = unmarked_program }, .{ .path = "notes.txt", .data = "text\n" } });
    defer project.deinit();
    const missing = try project.run("fix", "a.selka", &.{"missing.selka"});
    defer missing.deinit();
    try testing.expectEqual(@as(u8, 2), missing.status);
    try testing.expect(contains(missing.stderr, "cannot read 'missing.selka'"));
    try testing.expectEqualStrings("", missing.stdout);
    const first = try project.run("fix", "missing.selka", &.{"a.selka"});
    defer first.deinit();
    try testing.expectEqual(@as(u8, 2), first.status);
    const text = try project.run("fix", "a.selka", &.{"notes.txt"});
    defer text.deinit();
    try testing.expectEqual(@as(u8, 2), text.status);
    try testing.expect(contains(text.stderr, "notes.txt is neither a .selka entry nor a directory"));
    try expectFile(&project, "a.selka", unmarked_program);
}

// spec-case: FIX-FILE-2
test "CLI fix --check of a clean path and a dirty one lists the dirty one and exits 1, and exits 0 when both are clean" {
    var project = try Project.init(&.{ .{ .path = "clean.selka", .data = marked_program }, .{ .path = "dirty.selka", .data = unmarked_program } });
    defer project.deinit();
    const mixed = try project.run("fix", "clean.selka", &.{ "--check", "dirty.selka" });
    defer mixed.deinit();
    try testing.expectEqual(@as(u8, 1), mixed.status);
    try testing.expectEqualStrings("would fix dirty.selka: 1 edit " ++ marker_edit ++ "fix --check: 1 edit in 1 file would change\n", mixed.stdout);
    try expectFile(&project, "dirty.selka", unmarked_program);
    const repaired = try project.run("fix", "dirty.selka", &.{});
    defer repaired.deinit();
    try expectNothing(&project, "clean.selka", &.{ "--check", "dirty.selka" }, "");
}

// spec-case: FIX-FILE-2
test "CLI fix of paths that share a module with an error no repair clears prints it once, and exits 1" {
    var project = try Project.init(&.{
        .{ .path = "lib.selka", .data = "public func one() -> int:\n    return missing\n" },
        .{ .path = "main.selka", .data = "import lib\n\n\nfunc main() -> int:\n    return lib.one()\n" },
        .{ .path = "other.selka", .data = "import lib\n\n\nfunc main() -> int:\n    return lib.one()\n" },
    });
    defer project.deinit();
    const outcome = try project.run("fix", "main.selka", &.{ "other.selka", "--diagnostics=json" });
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.status);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.stderr, "\"code\":\"E_UNKNOWN_NAME\""));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.stderr, "\n"));
    try testing.expectEqualStrings("fix: nothing to fix\n", outcome.stdout);
}

// spec-case: FIX-FILE-2
test "CLI fix repairs a generated file that a later path names, and its status says how the files stand at the end" {
    var project = try Project.init(&.{
        .{ .path = "lib.selka", .data = "# generated by gen\n" ++ unmarked_module },
        .{ .path = "main.selka", .data = unmarked_importer },
    });
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{"lib.selka"});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("fixed lib.selka: 1 edit " ++ marker_edit ++ "fixed main.selka: 1 edit " ++ marker_edit ++
        "fix: 2 edits in 2 files over 2 rounds\n", fixed.stdout);
    try expectFile(&project, "lib.selka", "# generated by gen\nfunc bump(mut xs: int[]) -> Unit:\n    append(mut xs, 1)\n\n\npublic func grow(mut xs: int[]) -> Unit:\n    bump(mut xs)\n");
}

// R5B-MSGS 1: a bare `new_bitout()` and a parameter of type `BitOut` after `import bitio` are refused with the module that declares them, and
// `selka fix` writes the qualifier: the program then checks and runs.
test "CLI fix qualifies a bare name that an imported module declares" {
    const bitio =
        \\public record BitOut:
        \\    out: int[]
        \\
        \\
        \\public const LIMIT: int = 7
        \\
        \\
        \\public func new_bitout() -> BitOut:
        \\    return BitOut(out=[])
        \\
        \\
        \\public func put_bits(mut w: BitOut, value: int, count: int) -> Unit:
        \\    append(mut w.out, value + count)
        \\
    ;
    const main =
        \\import bitio
        \\
        \\
        \\func sides(w: BitOut) -> int:
        \\    return len(w.out)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut w = new_bitout()
        \\    put_bits(mut w, 1, 1)
        \\    print(out, sides(w) + LIMIT)
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = main }, .{ .path = "bitio.selka", .data = bitio } });
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:4:15: error[E_UNKNOWN_SYMBOL]: this module declares no `BitOut`; " ++
        "the imported module `bitio` declares it: write `bitio.BitOut`"));
    try testing.expect(contains(refused.stderr, "main.selka:9:13: error[E_UNKNOWN_SYMBOL]: this module declares no `new_bitout`; " ++
        "the imported module `bitio` declares it: write `bitio.new_bitout`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "func sides(w: bitio.BitOut) -> int:\n"));
    try testing.expect(contains(after, "    mut w = bitio.new_bitout()\n    bitio.put_bits(mut w, 1, 1)\n    print(out, sides(w) + bitio.LIMIT)\n"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("8\n", ran.stdout);
}

// R5B-MSGS 2: `try ` is written before a `fails` call used as its value when the enclosing function declares the same error type.
test "CLI fix writes try before a fails call used as its plain value" {
    const source =
        \\func parse(text: str) -> int fails str:
        \\    if len(text) == 0:
        \\        fail "empty"
        \\    return len(text)
        \\
        \\
        \\func show(n: int) -> int:
        \\    return n + 1
        \\
        \\
        \\func main(out: Stream) -> int fails str:
        \\    const total = 2 + parse("1")
        \\    const shown = show(parse("22"))
        \\    mut n: int = parse("333")
        \\    print(out, total + shown + n)
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "main.selka:12:21: error[E_TYPE]: expected int, found Result[int, str]; `parse` can fail: " ++
        "write `try parse(...)` to take its value and pass the error on, or handle it with `const n = parse(...) else Err(e):`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    const total = 2 + try parse(\"1\")\n    const shown = show(try parse(\"22\"))\n    mut n: int = try parse(\"333\")\n"));
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("9\n", ran.stdout);
}

// R5B-MSGS 2 (follow-up): `try` is refused in a contract condition, so the refusal of a `fails` call there names none and `selka fix` writes
// none: the file stays as it was, byte for byte.
test "CLI fix leaves a fails call in a contract condition as it is" {
    const source =
        \\func parse(text: str) -> int fails str:
        \\    if len(text) == 0:
        \\        fail "empty"
        \\    return len(text)
        \\
        \\
        \\@requires(parse(text) > 0)
        \\func guarded(text: str) -> int fails str:
        \\    return 1
        \\
        \\
        \\@ensures(result > parse(text))
        \\func after(text: str) -> int fails str:
        \\    return 100
        \\
        \\
        \\func main(out: Stream) -> int fails str:
        \\    print(out, try guarded("abc") + try after("x"))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const refused = try project.run("check", "main.selka", &.{});
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.status);
    try testing.expect(contains(refused.stderr, "error[E_TYPE]: expected"));
    try testing.expect(!contains(refused.stderr, "write `try parse(...)`"));
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try expectFile(&project, "main.selka", source);
}

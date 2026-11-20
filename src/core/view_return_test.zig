//! Views across module boundaries (wave 2 lane C-b, C5): a `str` function that
//! declares a borrowed slice result hands its caller a free view
//! when the caller is in another module, in every build mode, and an edit that
//! turns that view into a copy in the callee re-checks the caller.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const language = @import("selka");

const report = std.debug.print;

/// The callee module: `head` returns a slice of its parameter, a view.
const view_texts =
    \\public func head(source: str) -> str from source:
    \\    return source[0:4]
    \\
;

/// The same callee after the edit that makes every result a copy.
const copy_texts =
    \\public func head(source: str) -> str:
    \\    return copy(source[0:4])
    \\
;

/// The caller: one hundred cross-module calls over one built text.
const caller_source =
    \\import texts
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut data = "abcdefgh"
    \\    data = data + "ijkl"
    \\    mut total = 0
    \\    for i in range(100):
    \\        total += len(texts.head(data))
    \\    print(out, total)
    \\    return 0
    \\
;

/// Serves `main.selka` and `texts.selka` to the embedded project loader.
const Files = struct {
    texts: []const u8,

    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *const Files = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8, caller_source);
        if (std.mem.eql(u8, path, "texts.selka")) return allocator.dupe(u8, self.texts);
        return error.NotFound;
    }
};

/// The verified Core IR of the two-module project whose callee is `texts`.
fn projectWith(arena: std.mem.Allocator, texts: []const u8) !@import("ir.zig").Module {
    var files: Files = .{ .texts = texts };
    var program: language.embedded_project.Program = undefined;
    try program.init(arena, .{ .context = &files, .read = Files.read });
    var refusal: build.Refusal = .{};
    const module = try build.buildExecutable(arena, .{ .program = program.compilation.program.?, .source = program.compilation.src }, &refusal);
    try support.verified(arena, &module, &.{});
    return module;
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// The callee's result is a view in its own module's IR, and so is the call to it
// from the caller's module: no copy is built per call.
test "C5 a view result is a view in the caller's IR when the callee is in another module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try projectWith(a, view_texts);
    const dumped = try print.module(a, &module);
    try std.testing.expect(contains(dumped, "fn texts::head(str_view, str) -> str_view"));
    try std.testing.expect(contains(dumped, "call str_view texts::head"));
    try std.testing.expect(contains(dumped, "call str_view myl_core_view_slice_text(param0"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("400\n", ran.stdout);
}

/// The probe that calls `strings.strip` a hundred times over one built text (C7).
const strip_source =
    \\import strings
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut data = "  abcdefgh  "
    \\    data = data + " "
    \\    mut total = 0
    \\    for i in range(100):
    \\        total += len(strings.strip(data))
    \\    print(out, total)
    \\    return 0
    \\
;

/// Build `main.selka` in `root` with `flags` and a counting run, and return the
/// allocation count of the hundred calls.
fn allocationsOf(a: std.mem.Allocator, root: []const u8, flags: []const []const u8) !i64 {
    return allocationsOfProgram(a, root, flags, "400\n");
}

/// Build `main.selka` in `root` with `flags` and a counting run that must print
/// `expected`, and return the program's allocation count.
fn allocationsOfProgram(a: std.mem.Allocator, root: []const u8, flags: []const []const u8, expected: []const u8) !i64 {
    try support.requireReleaseArgs(flags);
    const input = try std.fs.path.join(a, &.{ root, "main.selka" });
    const binary = try std.fmt.allocPrint(a, "{s}/main-bin", .{root});
    const counters = try std.fmt.allocPrint(a, "{s}/counts.json", .{root});
    const cache = try std.fmt.allocPrint(a, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", cache, "--counters" });
    try argv.appendSlice(a, flags);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_COUNTERS", counters);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings(expected, ran.stdout);
    const json = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, counters, a, .limited(1 << 20));
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, json, .{});
    return parsed.object.get("totals").?.object.get("allocs").?.integer;
}

/// Write the project's two files into `root`.
fn writeProject(root: std.Io.Dir, texts: []const u8) !void {
    try root.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = caller_source });
    try root.writeFile(std.testing.io, .{ .sub_path = "texts.selka", .data = texts });
}

// A counted build allocates once for the hundred calls in every mode. Editing the
// callee to copy its result re-checks the caller, which then allocates per call,
// and restoring the view makes the next build free again, all in one cache.
test "C5 the view result holds in every build mode, and an edit to the callee re-checks the caller" {
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try writeProject(dir.dir, view_texts);
    try std.testing.expectEqual(@as(i64, 1), try allocationsOf(a, root, &.{}));
    try std.testing.expectEqual(@as(i64, 1), try allocationsOf(a, root, &.{"--unoptimized"}));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "texts.selka", .data = copy_texts });
    try std.testing.expectEqual(@as(i64, 101), try allocationsOf(a, root, &.{}));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "texts.selka", .data = view_texts });
    try std.testing.expectEqual(@as(i64, 1), try allocationsOf(a, root, &.{}));
    // An edit to the caller alone keeps the callee's unchanged body and its view.
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "# edited\n" ++ caller_source });
    try std.testing.expectEqual(@as(i64, 1), try allocationsOf(a, root, &.{}));
    try std.testing.expectEqual(@as(i64, 1), try allocationsOf(a, root, &.{"--release"}));
}

// The strip family answers a view of its argument (C7): a hundred calls of
// `strings.strip` allocate once, in release and in a debug build.
test "C7 strings.strip answers a view, so a hundred calls allocate once in release and debug" {
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = strip_source });
    try std.testing.expectEqual(@as(i64, 1), try allocationsOfProgram(a, root, &.{}, "800\n"));
    try std.testing.expectEqual(@as(i64, 1), try allocationsOfProgram(a, root, &.{"--release"}, "800\n"));
}

/// A loop that takes the length of each list element's stripped text, `rounds` times.
fn stripLoopSource(a: std.mem.Allocator, rounds: usize) ![]const u8 {
    return std.fmt.allocPrint(a,
        \\import strings
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut lines: str[] = []
        \\    for i in range(3):
        \\        append(mut lines, "  line " + str(i) + " words  ")
        \\    mut total = 0
        \\    for round in range({d}):
        \\        for line in lines:
        \\            total += len(strings.strip(line))
        \\    print(out, total)
        \\    return 0
        \\
    , .{rounds});
}

// The length of a stripped list element is read in place: a hundred rounds allocate
// exactly what one round does (the setup), so no call and no temporary copies its text.
test "C7 the length of a stripped list element is read in place, so a loop allocates nothing per round" {
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = try stripLoopSource(a, 1) });
    const once = try allocationsOfProgram(a, root, &.{"--release"}, "36\n");
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = try stripLoopSource(a, 100) });
    try std.testing.expectEqual(once, try allocationsOfProgram(a, root, &.{"--release"}, "3600\n"));
}

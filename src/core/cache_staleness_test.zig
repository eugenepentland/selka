//! Regression tests from the cache read audit (experiments/cache-read-audit-20261026,
//! docs/audits/provable-cache-plan-2026-10-26.md, package K0). Each test builds warm,
//! changes one input a cache did not cover, and requires the warm result to equal what a
//! clean (`--no-cache`) build of the same inputs produces.
const std = @import("std");
const tools = @import("core_test_options");

const Outcome = struct { status: u8, stdout: []const u8, stderr: []const u8 };

const trap_program =
    \\func main(out: Stream) -> int:
    \\    const xs: int[] = [1, 2, 3]
    \\    mut i = 5
    \\    print(out, "before")
    \\    return xs[i]
    \\
;

const link_program =
    \\extern func triple(host: Host, v: i32) -> i32
    \\
    \\func main(out: Stream, host: Host) -> int:
    \\    print(out, "triple", triple(host, 7))
    \\    return 0
    \\
;

const link_source = "int triple(int v) { return v * 3; }\n";

const warning_link_source = "#warning \"careful with the factor\"\nint triple(int v) { return v * 3; }\n";

/// A temporary project directory and the compiler commands run in it.
const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,

    fn write(self: Project, name: []const u8, bytes: []const u8) !void {
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try self.path(name), .data = bytes });
    }

    fn path(self: Project, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, name });
    }

    fn read(self: Project, name: []const u8) ![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(std.testing.io, try self.path(name), self.arena, .limited(64 << 20));
    }

    fn remove(self: Project, name: []const u8) !void {
        try std.Io.Dir.cwd().deleteFile(std.testing.io, try self.path(name));
    }

    /// Run the compiler with `args` in the project directory. The project counts its own
    /// replays: no shared stores.
    fn compiler(self: Project, args: []const []const u8) !Outcome {
        return self.compilerWith(args, &.{});
    }

    /// `compiler` with the variables in `extra` set (name, value) in its environment.
    fn compilerWith(self: Project, args: []const []const u8, extra: []const [2][]const u8) !Outcome {
        const executable = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, tools.corePath(), self.arena);
        const argv = try std.mem.concat(self.arena, []const u8, &.{ &.{executable}, args });
        var environment = try tools.privateEnvironment(self.arena);
        for (extra) |pair| try environment.put(pair[0], pair[1]);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = argv, .cwd = .{ .path = self.root }, .environ_map = &environment });
        const status: u8 = switch (result.term) {
            .exited => |code| code,
            else => 255,
        };
        return .{ .status = status, .stdout = result.stdout, .stderr = result.stderr };
    }

    /// `build` with a warm cache, then a clean `--no-cache` build of the same command:
    /// their programs, in `warm` and `clean`.
    fn warmAndClean(self: Project, args: []const []const u8) !struct { warm: []const u8, clean: []const u8 } {
        const warm = try self.compiler(try std.mem.concat(self.arena, []const u8, &.{ &.{ "build", "-o", "warm" }, args, &.{ "--cache-dir", "cache" } }));
        try std.testing.expectEqual(@as(u8, 0), warm.status);
        const clean = try self.compiler(try std.mem.concat(self.arena, []const u8, &.{ &.{ "build", "-o", "clean" }, args, &.{ "--cache-dir", "cache-clean", "--no-cache" } }));
        try std.testing.expectEqual(@as(u8, 0), clean.status);
        return .{ .warm = try self.read("warm"), .clean = try self.read("clean") };
    }
};

fn count(haystack: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, haystack, needle);
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a replayed build stands for the entry spelled as the command line gave it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("main.selka", trap_program);
    const absolute = try project.path("main.selka");
    // The program embeds the entry's path as spelled; a trap names it.
    const relative_run = try project.compiler(&.{ "run", "main.selka", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 1), relative_run.status);
    try std.testing.expect(std.mem.indexOf(u8, relative_run.stderr, absolute) == null);
    const absolute_run = try project.compiler(&.{ "run", absolute, "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 1), absolute_run.status);
    try std.testing.expect(std.mem.indexOf(u8, absolute_run.stderr, absolute) != null);
    // And the built bytes are the clean build's, whichever spelling warmed the cache.
    const primed = try project.compiler(&.{ "build", "main.selka", "-o", "primed", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 0), primed.status);
    const programs = try project.warmAndClean(&.{absolute});
    try std.testing.expectEqualSlices(u8, programs.clean, programs.warm);
    const dotted = try project.warmAndClean(&.{"./main.selka"});
    try std.testing.expectEqualSlices(u8, dotted.clean, dotted.warm);
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a replayed build stands for each --link source spelled as the command line gave it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("main.selka", link_program);
    try project.write("foo.c", link_source);
    // The object's debug information names the source as spelled, so the program's bytes do.
    const first = try project.warmAndClean(&.{ "main.selka", "--link", "foo.c" });
    try std.testing.expectEqualSlices(u8, first.clean, first.warm);
    const dotted = try project.warmAndClean(&.{ "main.selka", "--link", "./foo.c" });
    try std.testing.expectEqualSlices(u8, dotted.clean, dotted.warm);
    const absolute = try project.warmAndClean(&.{ "main.selka", "--link", try project.path("foo.c") });
    try std.testing.expectEqualSlices(u8, absolute.clean, absolute.warm);
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a replayed build adds no live warning twice and keeps none whose cause went away" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    const warning = "local standard module 'strings.selka' is ignored";
    try project.write("main.selka", "func main() -> int:\n    return 0\n");
    try project.write("strings.selka", "public func shadow() -> int:\n    return 1\n");
    const first = try project.compiler(&.{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 1), count(first.stderr, warning));
    // The record holds the warning with the listing it came from (the entry directory's names that
    // are standard modules), so it is printed once, from the record.
    const replayed = try project.compiler(&.{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache", "--cache-report" });
    try std.testing.expect(std.mem.indexOf(u8, replayed.stderr, "replayed") != null);
    try std.testing.expectEqual(@as(usize, 1), count(replayed.stderr, warning));
    // A file no standard module is named like leaves that listing, and the replay, as they were.
    try project.write("unrelated.selka", "public func unrelated() -> int:\n    return 2\n");
    const unrelated = try project.compiler(&.{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache", "--cache-report" });
    try std.testing.expect(std.mem.indexOf(u8, unrelated.stderr, "replayed") != null);
    try std.testing.expectEqual(@as(usize, 1), count(unrelated.stderr, warning));
    // A second shadowing file is a change of the listing: the build runs and warns for both.
    try project.write("math.selka", "public func shadow() -> int:\n    return 3\n");
    const second = try project.compiler(&.{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache", "--cache-report" });
    try std.testing.expect(std.mem.indexOf(u8, second.stderr, "replayed") == null);
    try std.testing.expectEqual(@as(usize, 1), count(second.stderr, warning));
    try std.testing.expectEqual(@as(usize, 1), count(second.stderr, "local standard module 'math.selka' is ignored"));
    try project.remove("math.selka");
    try project.remove("strings.selka");
    const cleared = try project.compiler(&.{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache", "--cache-report" });
    try std.testing.expect(std.mem.indexOf(u8, cleared.stderr, "replayed") == null);
    try std.testing.expectEqual(@as(usize, 0), count(cleared.stderr, warning));
    try std.testing.expectEqual(@as(usize, 0), count(cleared.stderr, "is ignored"));
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a body replayed from the checked-body store still warns about a deprecated callee" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("lib.selka", "@deprecated(\"use area2\")\npublic func area(side: int) -> int:\n    return side * side\n");
    try project.write("helper.selka", "import lib\n\npublic func uses_area(n: int) -> int:\n    return lib.area(n) + 1\n");
    try project.write("main.selka", "import helper\n\nfunc main(out: Stream) -> int:\n    print(out, \"main\", helper.uses_area(2))\n    return 0\n");
    try project.write("other.selka", "import helper\n\nfunc main(out: Stream) -> int:\n    print(out, \"other\", helper.uses_area(3))\n    return 0\n");
    const deprecated = "W_DEPRECATED";
    // Two entries share one cache directory and the module whose body makes the call.
    const first = try project.compiler(&.{ "build", "main.selka", "-o", "first", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 1), count(first.stderr, deprecated));
    const second = try project.compiler(&.{ "build", "other.selka", "-o", "second", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 1), count(second.stderr, deprecated));
    // The same module checked again, now by a command that holds no summaries for it (`--warnings`: the call is in the
    // imported `helper.selka`, whose warnings `check FILE` otherwise counts in one line).
    const checked = try project.compiler(&.{ "check", "other.selka", "--cache-dir", "cache", "--warnings" });
    try std.testing.expectEqual(@as(usize, 1), count(checked.stderr, deprecated));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a --link object served from the store repeats what the C compiler said when it was compiled" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("main.selka", link_program);
    try project.write("foo.c", warning_link_source);
    // The compiler prints the message and then the source line, so name the flag that ends the first.
    const warning = "[-W#warnings]";
    const first = try project.compiler(&.{ "build", "main.selka", "-o", "first", "--link", "foo.c", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 1), count(first.stderr, warning));
    // An edit to the program alone misses the replay and serves the C object from the store.
    try project.write("main.selka", try std.mem.replaceOwned(u8, project.arena, link_program, "\"triple\"", "\"thrice\""));
    const second = try project.compiler(&.{ "build", "main.selka", "-o", "second", "--link", "foo.c", "--cache-dir", "cache", "--cache-report" });
    try std.testing.expect(std.mem.indexOf(u8, second.stderr, "replayed") == null);
    try std.testing.expectEqual(@as(usize, 1), count(second.stderr, warning));
    const clean = try project.compiler(&.{ "build", "main.selka", "-o", "clean", "--link", "foo.c", "--cache-dir", "cache-clean", "--no-cache" });
    try std.testing.expectEqual(@as(usize, 1), count(clean.stderr, warning));
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a replayed body whose only use of an import is inside an f-string hole keeps the import used" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("util.selka", "public func twice(n: int) -> int:\n    return n * 2\n");
    const module =
        \\import util as u
        \\
        \\record Row:
        \\    name: int
        \\    reserved: bool
        \\
        \\func require_unique(table: Row[]):
        \\    for i in range(0, len(table)):
        \\        for j in range(i + 1, len(table)):
        \\            if table[i].name == table[j].name:
        \\                assert False, f"duplicate row '{u.twice(table[i].name)}'"
        \\
        \\public func guarded(n: int) -> int:
        \\    const table: Row[] = [Row(name=1, reserved=True), Row(name=2, reserved=True)]
        \\    require_unique(table)
        \\    return n
        \\
    ;
    try project.write("m.selka", module);
    try project.write("main.selka", "import m\n\nfunc main(out: Stream) -> int:\n    print(out, \"v\", m.guarded(3))\n    return 0\n");
    const first = try project.compiler(&.{ "build", "main.selka", "-o", "first", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 0), count(first.stderr, "W_UNUSED_IMPORT"));
    // Moving every line of the module replays its bodies from the checked-body store instead of standing them in.
    try project.write("m.selka", try std.mem.concat(project.arena, u8, &.{ "# moved\n", module }));
    const second = try project.compiler(&.{ "build", "main.selka", "-o", "second", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 0), count(second.stderr, "W_UNUSED_IMPORT"));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a header that appears beside a --link source changes its object although no depfile named it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    const source =
        \\#include <stdint.h>
        \\#include "stdbool.h"
        \\#if __has_include("opt.h")
        \\#define FACTOR 5
        \\#else
        \\#define FACTOR 3
        \\#endif
        \\int32_t triple(int32_t v) { return v * FACTOR * (true ? 1 : 0); }
        \\
    ;
    try project.write("main.selka", link_program);
    try project.write("foo.c", source);
    const arguments = [_][]const u8{ "main.selka", "--link", "foo.c" };
    const first = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, first.clean, first.warm);
    // `__has_include` finds a file the compiler had only asked about.
    try project.write("opt.h", "#define OPT 1\n");
    const second = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, second.clean, second.warm);
    // A quoted include is tried beside the source before the system directories.
    try project.write("stdbool.h", "#define true 0\n");
    const third = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, third.clean, third.warm);
    try std.testing.expect(!std.mem.eql(u8, first.warm, third.warm));
    try project.remove("opt.h");
    const fourth = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, fourth.clean, fourth.warm);
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a --link source that names its header through a macro follows a header that appears and shadows one it used" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    const source =
        \\#define LIMITS "limits.h"
        \\#include LIMITS
        \\#if __has_include("opt.h")
        \\#define EXTRA 5
        \\#else
        \\#define EXTRA 0
        \\#endif
        \\int triple(int v) { return v * (INT_MAX > 0 ? 3 : 1) + EXTRA; }
        \\
    ;
    try project.write("main.selka", link_program);
    try project.write("foo.c", source);
    const arguments = [_][]const u8{ "main.selka", "--link", "foo.c" };
    const first = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, first.clean, first.warm);
    // `__has_include` finds a file the compiler had only asked about.
    try project.write("opt.h", "#define OPT 1\n");
    const second = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, second.clean, second.warm);
    try std.testing.expect(!std.mem.eql(u8, first.warm, second.warm));
    // A header beside the source now shadows the system one the macro named.
    try project.write("limits.h", "#define INT_MAX -1\n");
    const third = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, third.clean, third.warm);
    try std.testing.expect(!std.mem.eql(u8, second.warm, third.warm));
    try project.remove("limits.h");
    const fourth = try project.warmAndClean(&arguments);
    try std.testing.expectEqualSlices(u8, fourth.clean, fourth.warm);
}

// spec-case: PROJECT-LINKS-1
test "run-project, build --run and test link the C sources a project's selka.json lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("main.selka", link_program);
    try project.write("foo.c", link_source);
    try project.write("selka.json", "{\"version\": 1, \"links\": [\"foo.c\"]}");
    try project.write("triple_test.selka",
        \\extern func triple(host: Host, v: i32) -> i32
        \\
        \\public func test_triple(host: Host) -> bool:
        \\    return int(triple(host, 7)) == 21
        \\
    );
    const ran = try project.compiler(&.{ "run-project", "main.selka", "--cache-dir", "cache" });
    try std.testing.expectEqualStrings("triple 21\n", ran.stdout);
    const built = try project.compiler(&.{ "build", "main.selka", "--run", "--cache-dir", "cache" });
    try std.testing.expectEqualStrings("triple 21\n", built.stdout);
    const tested = try project.compiler(&.{ "test", "triple_test.selka", "--allow-host", "--cache-dir", "cache-tests" });
    try std.testing.expectEqual(@as(u8, 0), tested.status);
    try std.testing.expect(std.mem.indexOf(u8, tested.stdout, "1 passed") != null);
    // Without the list, the symbol is missing: nothing else supplied it.
    try project.write("selka.json", "{\"version\": 1}");
    const unlinked = try project.compiler(&.{ "run-project", "main.selka", "--cache-dir", "cache" });
    try std.testing.expect(unlinked.status != 0);
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a --link source keyed by its preprocessed text is never served for another __TIME__" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("main.selka", link_program);
    try project.write("factor.h", "#define FACTOR 3\n");
    // The hour digit of `__TIME__` is added; `SOURCE_DATE_EPOCH` sets the clock the preprocessor reads.
    try project.write("foo.c", "#define HEADER \"factor.h\"\n#include HEADER\nint triple(int v) { return v * FACTOR + (__TIME__[1] - '0'); }\n");
    const arguments = [_][]const u8{ "run", "main.selka", "--link", "foo.c", "--cache-dir", "cache" };
    const midnight = try project.compilerWith(&arguments, &.{.{ "SOURCE_DATE_EPOCH", "0" }});
    try std.testing.expectEqualStrings("triple 21\n", midnight.stdout);
    const five = try project.compilerWith(&arguments, &.{.{ "SOURCE_DATE_EPOCH", "18000" }});
    try std.testing.expectEqualStrings("triple 26\n", five.stdout);
    const again = try project.compilerWith(&arguments, &.{.{ "SOURCE_DATE_EPOCH", "0" }});
    try std.testing.expectEqualStrings("triple 21\n", again.stdout);
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a --link source whose assembly includes a binary file is compiled by every build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    const source =
        \\#define HEADER "factor.h"
        \\#include HEADER
        \\extern const unsigned char blob[];
        \\__asm__(".section .rodata\n.globl blob\nblob:\n.incbin \"data.bin\"\n.previous\n");
        \\int triple(int v) { return v * FACTOR * blob[0]; }
        \\
    ;
    try project.write("main.selka", link_program);
    try project.write("factor.h", "#define FACTOR 3\n");
    try project.write("foo.c", source);
    try project.write("data.bin", "\x01");
    const arguments = [_][]const u8{ "run", "main.selka", "--link", "foo.c", "--cache-dir", "cache" };
    try std.testing.expectEqualStrings("triple 21\n", (try project.compiler(&arguments)).stdout);
    // The preprocessed text names `data.bin` but does not hold its bytes, so no key may stand for them.
    try project.write("data.bin", "\x02");
    try std.testing.expectEqualStrings("triple 42\n", (try project.compiler(&arguments)).stdout);
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a generic specialization that calls a deprecated function still warns after the entry is edited" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("lib.selka", "@deprecated(\"use area2\")\npublic func area(side: int) -> int:\n    return side * side\n");
    try project.write("helper.selka", "import lib\n\npublic func apply[T](value: T, n: int) -> T:\n    const used = lib.area(n)\n    if used > 0:\n        return value\n    return value\n");
    const entry = "import helper\n\nfunc main(out: Stream) -> int:\n    print(out, \"main\", helper.apply[int](5, 2))\n    return 0\n";
    try project.write("main.selka", entry);
    const first = try project.compiler(&.{ "build", "main.selka", "-o", "first", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 1), count(first.stderr, "W_DEPRECATED"));
    // The entry changes, the specialization does not: it is checked again rather than replayed without its warning.
    try project.write("main.selka", try std.mem.replaceOwned(u8, project.arena, entry, "\"main\"", "\"edited\""));
    const second = try project.compiler(&.{ "build", "main.selka", "-o", "second", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(usize, 1), count(second.stderr, "W_DEPRECATED"));
}

// spec-case: PROVABLE-CACHE-K1-ENV-1
test "a replay survives a changed terminal, locale or job count, and a changed keyed variable rebuilds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("main.selka", "func main() -> int:\n    return 3\n");
    const command = [_][]const u8{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache", "--cache-report" };
    const first = try project.compilerWith(&command, &.{.{ "TERM", "xterm" }});
    try std.testing.expectEqual(@as(u8, 0), first.status);
    try std.testing.expect(std.mem.indexOf(u8, first.stderr, "replayed") == null);
    // None of these can change the executable or the report, so none may defeat the replay.
    const harmless = [_][2][]const u8{ .{ "TERM", "dumb" }, .{ "COLUMNS", "40" }, .{ "LINES", "9" }, .{ "LANG", "C" }, .{ "TZ", "Asia/Tokyo" }, .{ "SELKA_JOBS", "1" } };
    for (harmless) |pair| {
        const again = try project.compilerWith(&command, &.{pair});
        try std.testing.expectEqual(@as(u8, 0), again.status);
        try std.testing.expect(std.mem.indexOf(u8, again.stderr, "replayed") != null);
    }
    // A variable the toolchain or the core reads does change what the build is.
    const keyed = try project.compilerWith(&command, &.{.{ "SOURCE_DATE_EPOCH", "1" }});
    try std.testing.expectEqual(@as(u8, 0), keyed.status);
    try std.testing.expect(std.mem.indexOf(u8, keyed.stderr, "replayed") == null);
    const keyed_again = try project.compilerWith(&command, &.{.{ "SOURCE_DATE_EPOCH", "1" }});
    try std.testing.expect(std.mem.indexOf(u8, keyed_again.stderr, "replayed") != null);
}

// spec-case: PROVABLE-CACHE-K1-LINK-1
test "a linked program's bytes do not depend on the project's directory, the command's, or the user's Zig cache" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var first_dir = std.testing.tmpDir(.{});
    defer first_dir.cleanup();
    var second_dir = std.testing.tmpDir(.{});
    defer second_dir.cleanup();
    const first: Project = .{ .arena = a, .root = try first_dir.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const second: Project = .{ .arena = a, .root = try second_dir.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const objects = try std.fs.path.join(a, &.{ try tools.suiteCache(a, @src()), "objects" });
    var programs: [2][]const u8 = undefined;
    for ([_]Project{ first, second }, 0..) |project, index| {
        try project.write("main.selka", "func main(out: Stream) -> int:\n    print(out, \"linked\", 1 + 2)\n    return 0\n");
        // Each build links into a Zig cache of its own that nothing has filled, from its own directory, with the
        // caller's Zig cache pointing at a third place: the C library stubs Zig makes carry the directory it ran in.
        const environment = [_][2][]const u8{
            .{ "SELKA_CORE_RUNTIME_CACHE", objects },
            .{ "XDG_CACHE_HOME", try project.path("xdg") },
            .{ "ZIG_GLOBAL_CACHE_DIR", try project.path("callers-zig-cache") },
        };
        const built = try project.compilerWith(&.{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache" }, &environment);
        try std.testing.expectEqual(@as(u8, 0), built.status);
        programs[index] = try project.read("prog");
    }
    try std.testing.expectEqualSlices(u8, programs[0], programs[1]);
}

// spec-case: PROVABLE-CACHE-K1-LINK-1
test "a --link object's manifest lists the system headers its compile opened, with their bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try project.write("main.selka", link_program);
    try project.write("foo.c", "#include <stdint.h>\n#include <stddef.h>\nint triple(int v) { return (int)(int32_t)v * 3; }\n");
    const built = try project.compiler(&.{ "build", "main.selka", "-o", "prog", "--cache-dir", "cache", "--link", "foo.c" });
    try std.testing.expectEqual(@as(u8, 0), built.status);
    // The manifest is the handle's record: the source and every header the compiler opened, system ones included.
    var directory = try std.Io.Dir.cwd().openDir(std.testing.io, try project.path("cache/foreign-v1"), .{ .iterate = true });
    defer directory.close(std.testing.io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    var manifests: usize = 0;
    var listed_system_header = false;
    while (try walker.next(std.testing.io)) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".deps")) continue;
        manifests += 1;
        const text = try directory.readFileAlloc(std.testing.io, entry.path, a, .limited(1 << 20));
        listed_system_header = std.mem.indexOf(u8, text, "/stdint.h\"") != null and std.mem.indexOf(u8, text, "/foo.c\"") != null;
    }
    try std.testing.expectEqual(@as(usize, 1), manifests);
    try std.testing.expect(listed_system_header);
}

const table_module =
    \\public record Entry:
    \\    name: str
    \\    run: func(int) -> int
    \\
    \\
    \\func one(x: int) -> int:
    \\    return x + 1
    \\
    \\
    \\func two(x: int) -> int:
    \\    return x * 2
    \\
    \\
    \\public func entries() -> Entry[]:
    \\    return [Entry(name="one", run=one), Entry(name="two", run=two)]
    \\
;

const table_entry =
    \\import note
    \\import tbl
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut total = 0
    \\    for e in tbl.entries():
    \\        const f = e.run
    \\        total += f(10)
    \\    print(out, "total", total, note.label())
    \\    return 0
    \\
;

/// `table_entry` over `table_module` built, edited in a module `tbl` does not import, and built again by `second_cache`'s work directory
/// (the first build's own, or another one the shared stores seed): the second build must link and run what a `--no-cache` build does.
fn expectWarmTableLinks(arena: std.mem.Allocator, first_cache: []const u8, second_cache: []const u8, shared: bool) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena) };
    try project.write("tbl.selka", table_module);
    try project.write("main.selka", table_entry);
    try project.write("note.selka", "public func label() -> str:\n    return \"a\"\n");
    const stores = [_][2][]const u8{
        .{ "SELKA_COMPILER_SHARED_CACHE", try project.path("shared-compiler") },
        .{ "SELKA_STAGE_SHARED_CACHE", try project.path("shared-stage") },
    };
    const environment: []const [2][]const u8 = if (shared) &stores else &.{};
    // `entries` is public and small, so the optimizer copies its function values into `main`, a unit of another module: `one` and `two`
    // must be visible to it although only their own module's source names them.
    const first = try project.compilerWith(&.{ "run", "main.selka", "--cache-dir", first_cache }, environment);
    try std.testing.expectEqual(@as(u8, 0), first.status);
    try std.testing.expectEqualStrings("total 31 a\n", first.stdout);
    // An edit elsewhere leaves `entries` unchanged, so the next check stands it in and has none of its checked nodes.
    try project.write("note.selka", "public func label() -> str:\n    return \"b\"\n");
    const warm = try project.compilerWith(&.{ "run", "main.selka", "--cache-dir", second_cache }, environment);
    const clean = try project.compiler(&.{ "run", "main.selka", "--cache-dir", "cache-clean", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), clean.status);
    try std.testing.expectEqualStrings("total 31 b\n", clean.stdout);
    try std.testing.expectEqual(clean.status, warm.status);
    try std.testing.expectEqualStrings(clean.stdout, warm.stdout);
    // The cached stages make the very units a fresh build makes, the linkage of `one` and `two` included (`--verify-cache`).
    const verified = try project.compilerWith(&.{ "build", "main.selka", "-o", "verified", "--cache-dir", second_cache, "--verify-cache" }, environment);
    try std.testing.expectEqual(@as(u8, 0), verified.status);
}

// spec-case: PROVABLE-CACHE-K0-PRIVATE-1
test "a private function that a public function's table names as a value links after a warm check stands that body in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectWarmTableLinks(arena.allocator(), "cache", "cache", false);
}

// spec-case: PROVABLE-CACHE-K0-PRIVATE-2
test "a private function that a public function's table names as a value links when the shared stores seed a cold work directory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectWarmTableLinks(arena.allocator(), "cache-first", "cache-second", true);
}

/// Proof steps S2: a caller's facts read its callee's return interval, which now takes the branches that dominate each
/// `ret`. `bound.selka` before and after an edit that widens `clamp` from [0, 2] to [0, 3]; `main.selka` indexes a three-element
/// list with it, so the bounds check is proved before the edit and must come back after it.
const bound_before =
    \\@ensures(result >= 0 and result < 3)
    \\public func clamp(value: int) -> int:
    \\    if value < 0:
    \\        return 0
    \\    if value > 2:
    \\        return 2
    \\    return value
    \\
;

const bound_after =
    \\@ensures(result >= 0 and result < 4)
    \\public func clamp(value: int) -> int:
    \\    if value < 0:
    \\        return 0
    \\    if value > 3:
    \\        return 3
    \\    return value
    \\
;

const bound_caller =
    \\import bound
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const xs: int[] = [10, 20, 30]
    \\    print(out, xs[bound.clamp(len(args))])
    \\    return 0
    \\
;

test "an edit to a callee that widens its return interval rebuilds the caller whose bounds check rested on it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try project.write("bound.selka", bound_before);
    try project.write("main.selka", bound_caller);
    const before = try project.compiler(&.{ "build", "main.selka", "-o", "before", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 0), before.status);
    const proved = try project.compiler(&.{ "cost", "main.selka", "main", "--cache-dir", "cache" });
    try std.testing.expect(std.mem.indexOf(u8, proved.stdout, "main: checks 0 kept") != null);
    // The callee alone changes; the caller's module is the same text.
    try project.write("bound.selka", bound_after);
    const programs = try project.warmAndClean(&.{"main.selka"});
    try std.testing.expectEqualSlices(u8, programs.clean, programs.warm);
    const kept = try project.compiler(&.{ "cost", "main.selka", "main", "--cache-dir", "cache" });
    try std.testing.expect(std.mem.indexOf(u8, kept.stdout, "main: checks 1 kept") != null);
    // The warm program checks the index again: four arguments make clamp return 3.
    const ran = try project.compiler(&.{ "run", "main.selka", "--cache-dir", "cache", "--", "a", "b", "c", "d" });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_LIST_BOUNDS") != null);
    const verified = try project.compiler(&.{ "build", "main.selka", "-o", "verified", "--cache-dir", "cache", "--verify-cache" });
    try std.testing.expectEqual(@as(u8, 0), verified.status);
}

//! rename: keep-file (the tests of the old variables below name them on purpose, and the rename program leaves the file alone).
//! The runtime's I/O limits (FR-021, FR-020). A whole read has no octet cap: it returns every byte of
//! a file past 64 MiB, and a read past the run's byte ceiling traps `R_MEMORY_BUDGET` rather than
//! stopping short. A reader that has gone from standard output or standard error ends the program quietly with status 141
//! (PIPE-1); any other refusal of standard output is the documented `R_OUTPUT` trap, never a signal.
const std = @import("std");
const testing = std.testing;

/// The big file's size: 65 MiB, past the old 64 MiB cap.
const big_size: usize = 65 * 1024 * 1024;
/// The last octets of the big file, so a read that stops short shows as a different tail.
const tail = "TAILMARK";

/// Reads the big file four ways: the text and bytes whole-path helpers, `File.read()` and `File.readline()`.
const reader =
    \\func whole(fs: Filesystem) -> str fails str:
    \\    with try fs.open("big.txt", "r") as f:
    \\        return f.read()
    \\
    \\
    \\func line(fs: Filesystem) -> str fails str:
    \\    with try fs.open("big.txt", "r") as f:
    \\        return f.readline()
    \\
    \\
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    match fs.read_text("big.txt"):
    \\        case Ok(text):
    \\            print(out, "read_text", len(text), text[len(text) - 8:len(text)])
    \\        case Err(message):
    \\            print(out, message)
    \\    match fs.read_file("big.txt"):
    \\        case Ok(data):
    \\            print(out, "read_file", len(data))
    \\        case Err(message):
    \\            print(out, message)
    \\    match whole(fs):
    \\        case Ok(text):
    \\            print(out, "read", len(text), text[len(text) - 8:len(text)])
    \\        case Err(message):
    \\            print(out, message)
    \\    match line(fs):
    \\        case Ok(text):
    \\            print(out, "readline", len(text))
    \\        case Err(message):
    \\            print(out, message)
    \\    return 0
    \\
;

/// Writes `big.txt` (`big_size` octets of `a` ending in `tail`, with no newline) and `main.selka` into `dir`.
fn writeFixtures(dir: std.Io.Dir, source: []const u8, name: []const u8) !void {
    const bytes = try testing.allocator.alloc(u8, big_size);
    defer testing.allocator.free(bytes);
    @memset(bytes[0 .. big_size - tail.len], 'a');
    @memcpy(bytes[big_size - tail.len ..], tail);
    try dir.writeFile(testing.io, .{ .sub_path = "big.txt", .data = bytes });
    try dir.writeFile(testing.io, .{ .sub_path = name, .data = source });
}

/// Compile `reader` in a fresh directory and run it with `extra` compiler flags.
fn runReader(extra: []const []const u8) !std.process.RunResult {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeFixtures(temporary.dir, reader, "reader.selka");
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compiler, "run", "reader.selka", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path });
    try argv.appendSlice(testing.allocator, extra);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = temporary.dir }, .environ_map = &environment });
}

test "a whole read of a file past 64 MiB returns every octet through each read path" {
    const result = try runReader(&.{});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings(
        \\read_text 68157440 TAILMARK
        \\read_file 68157440
        \\read 68157440 TAILMARK
        \\readline 68157440
        \\
    , result.stdout);
}

test "a whole read past the byte ceiling traps R_MEMORY_BUDGET instead of returning a prefix" {
    const result = try runReader(&.{"--max-memory=16M"});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expectEqualStrings("", result.stdout);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "R_MEMORY_BUDGET") != null);
}

/// A program that writes until its reader goes: its mode is its first argument. `print` prints 200,000 lines to standard output,
/// `large` writes one 4 MiB text to it, `err` prints 200,000 lines to standard error.
const pipe_writer =
    \\import strings
    \\
    \\func main(args: str[], out: Stream, err: Stream) -> int:
    \\    const mode = args[0]
    \\    match mode:
    \\        case "print":
    \\            for index in range(200000):
    \\                print(out, "line", index)
    \\        case "large":
    \\            write(out, strings.repeat("0123456789abcdef", 262144))
    \\        case "err":
    \\            for index in range(200000):
    \\                print(err, "line", index)
    \\        case _:
    \\            return 2
    \\    return 0
    \\
;

/// Write `pipe_writer` into `directory` and build it there as `writer`.
fn buildWriter(directory: std.Io.Dir, environment: *const std.process.Environ.Map, compiler: []const u8) !void {
    try directory.writeFile(testing.io, .{ .sub_path = "writer.selka", .data = pipe_writer });
    const built = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "writer.selka", "-o", "writer", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path },
        .cwd = .{ .dir = directory },
        .environ_map = environment,
    });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
}

/// Run `script` under `sh` in `directory`, with `arguments` as `$1`, `$2`, ... A program started inside `{ ...; } 3>&2 | head -c 1`
/// reports its status on file descriptor 3, which is the script's own standard error.
fn shell(directory: std.Io.Dir, environment: *const std.process.Environ.Map, script: []const u8, arguments: []const []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ "/bin/sh", "-c", script, "sh" });
    try argv.appendSlice(testing.allocator, arguments);
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = directory }, .environ_map = environment });
}

/// The standard error of a script that ran `program mode` with its reader gone: the status line alone means the program said nothing.
fn expectEndsQuietly(directory: std.Io.Dir, environment: *const std.process.Environ.Map, mode: []const u8, redirect: []const u8) !void {
    const script = try std.fmt.allocPrint(testing.allocator, "{{ \"$1\" \"$2\" {s}; echo \"status $?\" >&3; }} 3>&2 | head -c 1 >/dev/null", .{redirect});
    defer testing.allocator.free(script);
    const piped = try shell(directory, environment, script, &.{ "./writer", mode });
    defer testing.allocator.free(piped.stdout);
    defer testing.allocator.free(piped.stderr);
    try testing.expectEqualStrings("status 141\n", piped.stderr);
}

/// `selka run writer.selka -- mode` with its reader gone: the same status line alone, as `expectEndsQuietly` wants.
fn expectRunEndsQuietly(directory: std.Io.Dir, environment: *const std.process.Environ.Map, compiler: []const u8, mode: []const u8, redirect: []const u8) !void {
    const script = try std.fmt.allocPrint(testing.allocator, "{{ \"$1\" run writer.selka --cache-dir cache --zig=\"$2\" -- \"$3\" {s}; echo \"status $?\" >&3; }} 3>&2 | head -c 1 >/dev/null", .{redirect});
    defer testing.allocator.free(script);
    const run = try shell(directory, environment, script, &.{ compiler, @import("test_options").zig_path, mode });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqualStrings("status 141\n", run.stderr);
}

// spec-case: STREAM-PIPE-1
test "a reader that has gone from standard output or standard error ends the program quietly with status 141" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    try buildWriter(temporary.dir, &environment, compiler);
    // Standard output into a pipe whose reader exits after one octet: many small prints, then one large write.
    try expectEndsQuietly(temporary.dir, &environment, "print", "");
    try expectEndsQuietly(temporary.dir, &environment, "large", "");
    // Standard error into that pipe, standard output away.
    try expectEndsQuietly(temporary.dir, &environment, "err", "2>&1 >/dev/null");
    // `selka run` hands the program's status on: 141, and nothing of its own on standard error. Its own standard error is the
    // reader that goes for the program's, which `selka run` forwards, so that program ends the same way.
    try expectRunEndsQuietly(temporary.dir, &environment, compiler, "print", "");
    try expectRunEndsQuietly(temporary.dir, &environment, compiler, "err", "2>&1 >/dev/null");
}

// spec-case: STREAM-PIPE-1
test "a full disk behind standard output still traps R_OUTPUT, and a full disk behind standard error is still ignored" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    try buildWriter(temporary.dir, &environment, compiler);
    const full = try shell(temporary.dir, &environment, "\"$1\" print >/dev/full; echo \"status $?\" >&2", &.{"./writer"});
    defer testing.allocator.free(full.stdout);
    defer testing.allocator.free(full.stderr);
    try testing.expectEqualStrings("error[R_OUTPUT]: native execution failed\nstandard output refused a write\nstatus 1\n", full.stderr);
    const ignored = try shell(temporary.dir, &environment, "\"$1\" err 2>/dev/full >/dev/null; echo \"status $?\" >&2", &.{"./writer"});
    defer testing.allocator.free(ignored.stdout);
    defer testing.allocator.free(ignored.stderr);
    try testing.expectEqualStrings("status 0\n", ignored.stderr);
}

/// Appends a million integers (an 8 MiB list, more while it grows), then prints how many it holds.
const grower =
    \\func grow(mut values: int[], rounds: int) -> int:
    \\    for r in range(rounds):
    \\        append(mut values, r)
    \\    return len(values)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut values: int[] = []
    \\    print(out, "grew", grow(mut values, 1000000))
    \\    return 0
    \\
;

/// What the grower prints when no ceiling stops it.
const grown = "grew 1000000\n";
/// The first line of the grower's report when a ceiling stops it.
const budget_trap = "error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE\n";

/// The test process's environment with private stores and neither ceiling variable, so each case names its own.
fn ceilingEnvironment() !std.process.Environ.Map {
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    _ = environment.swapRemove("SELKA_MEMORY_LIMIT");
    _ = environment.swapRemove("SELKA_OPTIONS");
    return environment;
}

/// Write `grower` into `directory` and build it there as `grower` with `selka build -o`.
fn buildGrower(directory: std.Io.Dir, environment: *const std.process.Environ.Map, compiler: []const u8) !void {
    try directory.writeFile(testing.io, .{ .sub_path = "grower.selka", .data = grower });
    const built = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "grower.selka", "-o", "grower", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path },
        .cwd = .{ .dir = directory },
        .environ_map = environment,
    });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
}

/// How a case ends: its status, all of its standard output, and the start of its standard error.
const Outcome = struct { status: u8, stdout: []const u8, stderr: []const u8 };
/// The grower ran to its end.
const ran: Outcome = .{ .status = 0, .stdout = grown, .stderr = "" };
/// A ceiling stopped the grower.
const trapped: Outcome = .{ .status = 1, .stdout = "", .stderr = budget_trap };

/// `argv` run in `directory` with each `variables` pair (a name and its value) set over `environment` ends as `outcome` says.
fn expectCeiling(directory: std.Io.Dir, environment: *const std.process.Environ.Map, argv: []const []const u8, variables: []const [2][]const u8, outcome: Outcome) !void {
    var changed = try environment.clone(testing.allocator);
    defer changed.deinit();
    for (variables) |pair| try changed.put(pair[0], pair[1]);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv, .cwd = .{ .dir = directory }, .environ_map = &changed });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqualStrings(outcome.stdout, result.stdout);
    try testing.expectStringStartsWith(result.stderr, outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = outcome.status }, result.term);
}

test "a built binary takes --max-memory in SELKA_OPTIONS, then SELKA_MEMORY_LIMIT, and no ceiling when neither is set" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try ceilingEnvironment();
    defer environment.deinit();
    try buildGrower(temporary.dir, &environment, compiler);
    const program: []const []const u8 = &.{"./grower"};
    try expectCeiling(temporary.dir, &environment, program, &.{}, ran);
    try expectCeiling(temporary.dir, &environment, program, &.{.{ "SELKA_MEMORY_LIMIT", "4M" }}, trapped);
    try expectCeiling(temporary.dir, &environment, program, &.{.{ "SELKA_OPTIONS", "--max-memory=4M" }}, trapped);
    // The option outranks the variable, and `0` removes the ceiling either way.
    try expectCeiling(temporary.dir, &environment, program, &.{ .{ "SELKA_OPTIONS", "--max-memory=1G" }, .{ "SELKA_MEMORY_LIMIT", "4M" } }, ran);
    try expectCeiling(temporary.dir, &environment, program, &.{ .{ "SELKA_OPTIONS", "--max-memory=0" }, .{ "SELKA_MEMORY_LIMIT", "4M" } }, ran);
    try expectCeiling(temporary.dir, &environment, program, &.{.{ "SELKA_MEMORY_LIMIT", "0" }}, ran);
    // A size that is not one is the usual option error, before the program runs.
    try expectCeiling(temporary.dir, &environment, program, &.{.{ "SELKA_MEMORY_LIMIT", "12x" }}, .{ .status = 2, .stdout = "", .stderr = "selka: SELKA_MEMORY_LIMIT names 12x, which is not a byte size\n" });
    try expectCeiling(temporary.dir, &environment, program, &.{.{ "SELKA_OPTIONS", "--max-memory=12x" }}, .{ .status = 2, .stdout = "", .stderr = "selka: SELKA_OPTIONS names --max-memory=12x, which is not a byte size\n" });
}

test "selka run applies its own ceiling, not the SELKA_MEMORY_LIMIT its program inherits, after a built binary of the same program" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try ceilingEnvironment();
    defer environment.deinit();
    // The binary's entry is cached first, so a run that reused it would read the variable as the binary does.
    try buildGrower(temporary.dir, &environment, compiler);
    const run = .{ compiler, "run", "grower.selka", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path };
    try expectCeiling(temporary.dir, &environment, &(run ++ .{"--max-memory=1G"}), &.{.{ "SELKA_MEMORY_LIMIT", "1" }}, ran);
    try expectCeiling(temporary.dir, &environment, &(run ++ .{"--max-memory=1G"}), &.{.{ "SELKA_MEMORY_LIMIT", "junk" }}, ran);
    try expectCeiling(temporary.dir, &environment, &(run ++ .{"--max-memory=0"}), &.{.{ "SELKA_MEMORY_LIMIT", "4M" }}, ran);
    try expectCeiling(temporary.dir, &environment, &run, &.{.{ "SELKA_MEMORY_LIMIT", "4M" }}, trapped);
}

/// What a built program says and how it ends when `MYLANG_OPTIONS` is set and `SELKA_OPTIONS` is not (one release of hints).
const old_options: Outcome = .{ .status = 2, .stdout = "", .stderr = "selka: MYLANG_OPTIONS is set and SELKA_OPTIONS is not: the variable is named SELKA_OPTIONS now, and this program ignores the old name\n" };
/// The same for `MYLANG_MEMORY_LIMIT` and `SELKA_MEMORY_LIMIT`.
const old_limit: Outcome = .{ .status = 2, .stdout = "", .stderr = "selka: MYLANG_MEMORY_LIMIT is set and SELKA_MEMORY_LIMIT is not: the variable is named SELKA_MEMORY_LIMIT now, and this program ignores the old name\n" };

test "a built binary ends with status 2 before main when MYLANG_OPTIONS or MYLANG_MEMORY_LIMIT is set and its SELKA_ spelling is not" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try ceilingEnvironment();
    defer environment.deinit();
    try buildGrower(temporary.dir, &environment, compiler);
    const program: []const []const u8 = &.{"./grower"};
    try expectCeiling(temporary.dir, &environment, program, &.{.{ "MYLANG_OPTIONS", "--restrict" }}, old_options);
    try expectCeiling(temporary.dir, &environment, program, &.{.{ "MYLANG_MEMORY_LIMIT", "4M" }}, old_limit);
    // The options come first when both are set, and neither old name is honoured: the program did not run with the ceiling.
    try expectCeiling(temporary.dir, &environment, program, &.{ .{ "MYLANG_MEMORY_LIMIT", "4M" }, .{ "MYLANG_OPTIONS", "--restrict" } }, old_options);
    // With the new spelling set the old one is not looked at, and an empty old variable asks for nothing.
    try expectCeiling(temporary.dir, &environment, program, &.{ .{ "MYLANG_OPTIONS", "--restrict" }, .{ "SELKA_OPTIONS", "--max-memory=1G" } }, ran);
    try expectCeiling(temporary.dir, &environment, program, &.{ .{ "MYLANG_MEMORY_LIMIT", "4M" }, .{ "SELKA_MEMORY_LIMIT", "1G" } }, ran);
    try expectCeiling(temporary.dir, &environment, program, &.{ .{ "MYLANG_OPTIONS", "" }, .{ "MYLANG_MEMORY_LIMIT", "" } }, ran);
    // The old name never sets the ceiling: the new spelling alone does.
    try expectCeiling(temporary.dir, &environment, program, &.{ .{ "MYLANG_MEMORY_LIMIT", "1G" }, .{ "SELKA_MEMORY_LIMIT", "4M" } }, trapped);
}

/// `argv` run in `directory` with `variables` set over `environment` ends with status 2, prints nothing on standard output, and
/// has every one of `lines` on standard error.
fn expectRefused(directory: std.Io.Dir, environment: *const std.process.Environ.Map, argv: []const []const u8, variables: []const [2][]const u8, lines: []const []const u8) !void {
    var changed = try environment.clone(testing.allocator);
    defer changed.deinit();
    for (variables) |pair| try changed.put(pair[0], pair[1]);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv, .cwd = .{ .dir = directory }, .environ_map = &changed });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqualStrings("", result.stdout);
    for (lines) |line| try testing.expect(std.mem.indexOf(u8, result.stderr, line) != null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
}

test "selka run and selka test end with status 2 under the same condition, and the compiler names the variable first" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try ceilingEnvironment();
    defer environment.deinit();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "grower.selka", .data = grower });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "grower_test.selka", .data = "public func test_ok() -> bool:\n    return True\n" });
    const hint = "selka: the variable MYLANG_OPTIONS is set and SELKA_OPTIONS is not: variables begin with SELKA_ now, and the old name is ignored\n";
    const run = [_][]const u8{ compiler, "run", "grower.selka", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path };
    try expectRefused(temporary.dir, &environment, &run, &.{.{ "MYLANG_OPTIONS", "--restrict" }}, &.{ hint, old_options.stderr });
    const test_run = [_][]const u8{ compiler, "test", "grower_test.selka", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path };
    try expectRefused(temporary.dir, &environment, &test_run, &.{.{ "MYLANG_OPTIONS", "--restrict" }}, &.{hint});
}

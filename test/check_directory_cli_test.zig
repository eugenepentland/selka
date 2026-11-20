//! `selka check DIR` checks every module of the project beneath DIR, imported or not
//! (F-G2d-1: `check ENTRY` never type-checked a module the entry does not import).
const std = @import("std");
const testing = std.testing;

/// What one `selka check` of a fixture project printed, and how it ended.
const Outcome = struct { code: u8, stdout: []u8, stderr: []u8 };

/// A project of `files` (path and text pairs) in a fresh directory, checked by `selka check ARGUMENT --no-cache`
/// run from that directory.
fn checked(files: []const [2][]const u8, argument: []const u8) !Outcome {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    for (files) |file| {
        if (std.fs.path.dirname(file[0])) |parent| try temporary.dir.createDirPath(testing.io, parent);
        try temporary.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    }
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "check", argument, "--no-cache" },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    return .{ .code = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .stdout = result.stdout, .stderr = result.stderr };
}

fn release(outcome: Outcome) void {
    testing.allocator.free(outcome.stdout);
    testing.allocator.free(outcome.stderr);
}

const config = [2][]const u8{ "selka.json", "{\"version\": 1}\n" };
const main_source = [2][]const u8{ "main.selka", "func main() -> int:\n    return 0\n" };
const orphan_with_error = [2][]const u8{ "orphan.selka", "public func f() -> int:\n    x = 1\n    return x\n" };
const orphan_clean = [2][]const u8{ "orphan.selka", "public func f() -> int:\n    return 1\n" };

test "check DIR: checking the entry alone never sees a module nothing imports, and checking the directory does (F-G2d-1)" {
    const entry = try checked(&.{ config, main_source, orphan_with_error }, "main.selka");
    defer release(entry);
    try testing.expectEqual(@as(u8, 0), entry.code);
    const directory = try checked(&.{ config, main_source, orphan_with_error }, ".");
    defer release(directory);
    try testing.expectEqual(@as(u8, 1), directory.code);
    try testing.expect(std.mem.indexOf(u8, directory.stderr, "orphan.selka:2:5: error[E_BINDING_DECLARATION]") != null);
}

test "check DIR: a clean project reports the modules of the project, not the generated entry" {
    const outcome = try checked(&.{ config, main_source, orphan_clean, .{ "sub/leaf.selka", "public func g() -> int:\n    return 2\n" } }, ".");
    defer release(outcome);
    try testing.expectEqual(@as(u8, 0), outcome.code);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "check: ok (3 modules, 0 cached)") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "selka_check_all") == null);
}

test "check DIR: a test module nobody imports keeps its access to the private declarations of the module it tests" {
    const files = [_][2][]const u8{
        config,
        .{ "shape.selka", "func hidden() -> int:\n    return 4\n\npublic func shown() -> int:\n    return hidden()\n" },
        .{ "shape_test.selka", "import shape\n\npublic func test_hidden() -> bool:\n    return shape.hidden() == 4\n" },
    };
    const outcome = try checked(&files, ".");
    defer release(outcome);
    try testing.expectEqual(@as(u8, 0), outcome.code);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "E_PRIVATE_SYMBOL") == null);
}

test "check DIR: a directory check names a file it skipped because its name is no module name" {
    const outcome = try checked(&.{ config, main_source, .{ "bad-name.selka", "" } }, ".");
    defer release(outcome);
    try testing.expectEqual(@as(u8, 0), outcome.code);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "check: skipped 1 file whose names are not module names: bad-name.selka") != null);
}

test "check DIR: a directory check reports the warnings of the modules and none of its generated entry" {
    const outcome = try checked(&.{ config, main_source, .{ "uses.selka", "import orphan\n\npublic func h() -> int:\n    return 3\n" }, orphan_clean }, ".");
    defer release(outcome);
    try testing.expectEqual(@as(u8, 0), outcome.code);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "uses.selka:1:8: warning[W_UNUSED_IMPORT]") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "selka_check_all") == null);
}

test "check DIR: a project that holds a module named like the generated entry is refused with exit status 2" {
    const outcome = try checked(&.{ config, main_source, .{ "selka_check_all.selka", "" } }, ".");
    defer release(outcome);
    try testing.expectEqual(@as(u8, 2), outcome.code);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "the name of the entry a directory check generates") != null);
}

test "check DIR prints a warning of a file the project reaches through a symbolic link and by its own path once (FR14)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(testing.io, "lib");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib/shout.selka", .data = "public func loud(x: int) -> bool:\n    return x >= 1 and x <= 5\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import shout\n\n\nfunc main() -> int:\n    if shout.loud(2):\n        return 0\n    return 1\n" });
    try temporary.dir.symLink(testing.io, "lib/shout.selka", "shout.selka", .{});
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "check", ".", "--warnings", "--no-cache" },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(@as(u8, 0), switch (result.term) {
        .exited => |code| code,
        else => 255,
    });
    // The file is loaded as `lib.shout` (the directory's own walk) and as `shout` (main's import through the link).
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "warning[W_RANGE_CHAIN]"));
    try testing.expect(std.mem.indexOf(u8, result.stderr, "lib/shout.selka:2:12: warning[W_RANGE_CHAIN]") != null);
}

/// A library with one `W_COPY_MOVE` hint of each rule that a caller makes `check` leave out, and one of each that stays
/// (FR14b): `https_url`'s result is kept by `ward`, `names_of`'s list is still needed by `count`, and `passed`'s result is
/// returned by `relay`, which `from` would refuse there. `label`'s callers only read its result and `lines_of`'s caller gives
/// its list, and the project is no package, so their hints are the `W_COPY_RETURNED` and `W_COPY_FOR_STORE` warnings with the
/// repair in their place (COPY-A2c, COPY-A3d, COPY-FROM-PUBLIC).
const copy_move_library = [2][]const u8{
    "src/lib.selka",
    \\public record Holder:
    \\    url: str
    \\
    \\
    \\public record Use:
    \\    name: str
    \\    line: int
    \\
    \\
    \\public func https_url(url: str) -> str:
    \\    if url == "":
    \\        return "none"
    \\    return copy(url)
    \\
    \\
    \\public func label(status: str) -> str:
    \\    if status == "":
    \\        return "none"
    \\    return copy(status)
    \\
    \\
    \\public func names_of(uses: Use[]) -> str[]:
    \\    mut names: str[] = []
    \\    for use in uses:
    \\        append(mut names, copy(use.name))
    \\    return names
    \\
    \\
    \\public func lines_of(uses: Use[]) -> str[]:
    \\    mut lines: str[] = []
    \\    for use in uses:
    \\        append(mut lines, copy(use.name))
    \\    return lines
    \\
    \\
    \\public func ward(url: str) -> Holder:
    \\    return Holder(url=https_url(url))
    \\
    \\
    \\public func passed(status: str) -> str:
    \\    if status == "":
    \\        return "none"
    \\    return copy(status)
    \\
};

const copy_move_main =
    \\import lib
    \\
    \\
    \\func count(uses: lib.Use[]) -> int:
    \\    return len(lib.names_of(uses)) + len(uses)
    \\
    \\
    \\func relay(status: str) -> str:
    \\    return lib.passed(status)
    \\
    \\
    \\func main() -> int:
    \\    const h = lib.ward("https://a")
    \\    const uses = [lib.Use(name="a", line=1)]
    \\    const more = [lib.Use(name="b", line=2)]
    \\    return len(h.url) + len(lib.label("q")) + count(uses) + len(lib.lines_of(more)) + len(relay("r"))
    \\
;

/// `selka check src --warnings` of the project in `directory` through the work directory `cache` (relative to it), with the
/// shared stores off; the standard error without its last line, the `check: ok (N modules, M cached)` line whose count of
/// cached modules is the one thing a reuse may change.
fn checkWarnings(directory: std.Io.Dir, cache: []const u8) ![]u8 {
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const flag = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(flag);
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "check", "src", "--warnings", flag },
        .cwd = .{ .dir = directory },
        .environ_map = &environment,
    });
    defer testing.allocator.free(result.stdout);
    errdefer testing.allocator.free(result.stderr);
    try testing.expectEqual(@as(u8, 0), switch (result.term) {
        .exited => |code| code,
        else => 255,
    });
    // The `check: ok (` line is the last one, or the one before the line that counts what `selka fix` would repair.
    const trimmed = std.mem.trimEnd(u8, result.stderr, "\n");
    const last = std.mem.lastIndexOf(u8, trimmed, "\ncheck: ok (") orelse 0;
    try testing.expect(std.mem.startsWith(u8, std.mem.trimStart(u8, trimmed[last..], "\n"), "check: ok ("));
    const after = std.mem.indexOfScalarPos(u8, trimmed, last + 1, '\n') orelse trimmed.len;
    const kept = try std.mem.concat(testing.allocator, u8, &.{ trimmed[0..last], trimmed[after..] });
    testing.allocator.free(result.stderr);
    return kept;
}

// spec-case: CHECK-SUMMARY-1
test "check DIR prints the same W_COPY_MOVE hints cold, with unchanged bodies stood in from its summaries, and replayed (FR14b)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(testing.io, "src");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = copy_move_library[0], .data = copy_move_library[1] });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "src/main.selka", .data = copy_move_main });
    const first = try checkWarnings(temporary.dir, "warm-cache");
    defer testing.allocator.free(first);
    // An edit of the entry module alone: the library's bodies stand in from the summaries of the first check.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "src/main.selka", .data = copy_move_main ++ "\n\nfunc spare() -> int:\n    return 2\n" });
    const warm = try checkWarnings(temporary.dir, "warm-cache");
    defer testing.allocator.free(warm);
    const replayed = try checkWarnings(temporary.dir, "warm-cache");
    defer testing.allocator.free(replayed);
    const cold = try checkWarnings(temporary.dir, "cold-cache");
    defer testing.allocator.free(cold);
    // The filter left out `https_url`'s and `names_of`'s hints and kept `passed`'s; `label`'s and `lines_of`'s are the warnings
    // that repair them.
    try testing.expect(std.mem.indexOf(u8, cold, "warning[W_COPY_MOVE]: every return of `passed` copies a place of `status`") != null);
    try testing.expect(std.mem.indexOf(u8, cold, "warning[W_COPY_RETURNED]: every return of `label` copies a place of `status`") != null);
    try testing.expect(std.mem.indexOf(u8, cold, "`label` is public, so its signature changes") != null);
    try testing.expect(std.mem.indexOf(u8, cold, "`for use in own uses` hands the elements over") == null);
    try testing.expect(std.mem.indexOf(u8, cold, "lib.selka:32:27: warning[W_COPY_FOR_STORE]: `lines_of` copies each element of parameter `uses` into storage it keeps") != null);
    try testing.expect(std.mem.indexOf(u8, cold, "`lines_of` is public, so its signature changes") != null);
    try testing.expect(std.mem.indexOf(u8, cold, "https_url") == null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, cold, "warning[W_COPY_MOVE]"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, cold, "lib.selka:32:"));
    try testing.expectEqualStrings(cold, first);
    try testing.expectEqualStrings(cold, warm);
    try testing.expectEqualStrings(cold, replayed);
    // `fix --check` checks each entry and forwards what the checks print: the same from the warm work directory as from a cold one.
    const fixed_warm = try fixCheck(temporary.dir, "warm-cache");
    defer testing.allocator.free(fixed_warm);
    const fixed_cold = try fixCheck(temporary.dir, "fix-cold-cache");
    defer testing.allocator.free(fixed_cold);
    try testing.expect(std.mem.indexOf(u8, fixed_cold, "https_url") == null);
    try testing.expectEqualStrings(fixed_cold, fixed_warm);
}

/// `selka fix --check src` of the project in `directory` through the work directory `cache`, with the shared stores off:
/// standard output and standard error together.
fn fixCheck(directory: std.Io.Dir, cache: []const u8) ![]u8 {
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const flag = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(flag);
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "fix", "--check", "src", flag },
        .cwd = .{ .dir = directory },
        .environ_map = &environment,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    return std.mem.concat(testing.allocator, u8, &.{ result.stdout, result.stderr });
}

const ward_library =
    \\public record Holder:
    \\    url: str
    \\
    \\
    \\public func norm(n: int) -> int:
    \\    return n + 1
    \\
    \\
    \\public func https_url(url: str) -> str:
    \\    if url == "" and norm(1) > 0:
    \\        return "none"
    \\    return "fixed"
    \\
;

const ward_keeper = "import lib\n\n\npublic func ward(url: str) -> lib.Holder:\n    return lib.Holder(url=lib.https_url(url))\n";
const ward_main = "import keep\n\n\nfunc main() -> int:\n    return len(keep.ward(\"https://a\").url)\n";

/// Write `data` over `path` in `directory`, then check the project warm (work directory `warm`) and cold (a new work
/// directory `cold-<step>`) and expect the same output.
fn sameAfter(directory: std.Io.Dir, path: []const u8, data: []const u8, step: []const u8) ![]u8 {
    try directory.writeFile(testing.io, .{ .sub_path = path, .data = data });
    const warm = try checkWarnings(directory, "warm");
    errdefer testing.allocator.free(warm);
    const cold_cache = try std.fmt.allocPrint(testing.allocator, "cold-{s}", .{step});
    defer testing.allocator.free(cold_cache);
    const cold = try checkWarnings(directory, cold_cache);
    defer testing.allocator.free(cold);
    try testing.expectEqualStrings(cold, warm);
    return warm;
}

// spec-case: CHECK-SUMMARY-1
test "check DIR judges W_COPY_MOVE hints as a cold check does after each edit that can change a hint or a caller's answer (FR14b)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const d = temporary.dir;
    try d.createDirPath(testing.io, "src");
    try d.writeFile(testing.io, .{ .sub_path = "src/lib.selka", .data = ward_library });
    try d.writeFile(testing.io, .{ .sub_path = "src/keep.selka", .data = ward_keeper });
    try d.writeFile(testing.io, .{ .sub_path = "src/main.selka", .data = ward_main });
    testing.allocator.free(try checkWarnings(d, "warm"));
    // The callee gains the hint while its keeping caller, in a module the edit leaves alone, stands in.
    const gained = try std.mem.replaceOwned(u8, testing.allocator, ward_library, "return \"fixed\"", "return copy(url)");
    defer testing.allocator.free(gained);
    const step1 = try sameAfter(d, "src/lib.selka", gained, "1");
    defer testing.allocator.free(step1);
    try testing.expect(std.mem.indexOf(u8, step1, "W_COPY_MOVE") == null);
    // An edit elsewhere: the callee and its keeper both stand in, the hint and the answer come from their summaries.
    const step2 = try sameAfter(d, "src/main.selka", ward_main ++ "\n\nfunc spare() -> int:\n    return 2\n", "2");
    defer testing.allocator.free(step2);
    // The body of a function the callee calls changes; the callee and its keeper stand in.
    const callee_callee = try std.mem.replaceOwned(u8, testing.allocator, gained, "return n + 1", "return n + 2");
    defer testing.allocator.free(callee_callee);
    const step3 = try sameAfter(d, "src/lib.selka", callee_callee, "3");
    defer testing.allocator.free(step3);
    // The callee's signature alone: its parameter is renamed, and the hint names the new one.
    const renamed_head = try std.mem.replaceOwned(u8, testing.allocator, callee_callee, "https_url(url: str)", "https_url(link: str)");
    defer testing.allocator.free(renamed_head);
    const renamed_test = try std.mem.replaceOwned(u8, testing.allocator, renamed_head, "if url ==", "if link ==");
    defer testing.allocator.free(renamed_test);
    const renamed = try std.mem.replaceOwned(u8, testing.allocator, renamed_test, "copy(url)", "copy(link)");
    defer testing.allocator.free(renamed);
    const step4 = try sameAfter(d, "src/lib.selka", renamed, "4");
    defer testing.allocator.free(step4);
    // A type the keeper builds gains a field.
    const typed_edit = try std.mem.replaceOwned(u8, testing.allocator, renamed, "    url: str\n", "    url: str\n    port: int = 443\n");
    defer testing.allocator.free(typed_edit);
    const step5 = try sameAfter(d, "src/lib.selka", typed_edit, "5");
    defer testing.allocator.free(step5);
    try testing.expect(std.mem.indexOf(u8, step5, "W_COPY_MOVE") == null);
    // The keeping caller goes away: the hint is printed again, as a cold check prints it.
    const step6 = try sameAfter(d, "src/keep.selka", "import lib\n\n\npublic func ward(url: str) -> lib.Holder:\n    const n = len(lib.https_url(url))\n    return lib.Holder(url=str(n))\n", "6");
    defer testing.allocator.free(step6);
    try testing.expect(std.mem.indexOf(u8, step6, "every return of `https_url` copies a place of `link`") != null);
}

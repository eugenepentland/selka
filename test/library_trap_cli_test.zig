//! A trap inside a standard-library body leads its report with the program's own line (FX18). The
//! report's first line names the nearest frame outside the library, the library frame follows it
//! as context, then the program's callers; a trap inside a C operation the library calls
//! (`strings.find`'s `find_offset`) lists those callers too. One case per trapping library function
//! of the table in `experiments/audit-work-20261111/FX18.md`, plus a key function of the program
//! that traps inside a library sort, whose report already starts in the program. The program is
//! built once (and once with `--release` under `-Dtest-release`), and each case is one run of it with the case's number.
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// Release halves run only under `-Dtest-release=true` (the user's decision of 28 October 2026).
fn requireRelease() error{SkipZigTest}!void {
    if (!@import("test_release_options").enabled) return error.SkipZigTest;
}

/// One trapping call: the argument that selects it, the code, the location the report's first
/// line names, and the library function its first frame names (null: a trap in the program).
const Case = struct { argument: []const u8, code: []const u8, at: []const u8, library: ?[]const u8 };

const cases = [_]Case{
    .{ .argument = "00", .code = "R_TEXT_BOUNDARY", .at = "probe.selka:11:12", .library = "strings::find" }, // strings.find (bound inside a character)
    .{ .argument = "01", .code = "R_TEXT_BOUNDS", .at = "probe.selka:15:12", .library = "strings::find" }, // strings.find (negative bound)
    .{ .argument = "02", .code = "R_TEXT_BOUNDARY", .at = "probe.selka:19:12", .library = "strings::rfind" }, // strings.rfind (bound inside a character)
    .{ .argument = "03", .code = "R_LIST_BOUNDS", .at = "probe.selka:23:16", .library = "bytes::read_u8" }, // bytes.read_u8 (offset past the end)
    .{ .argument = "04", .code = "R_LIST_BOUNDS", .at = "probe.selka:27:16", .library = "bytes::read_i8" }, // bytes.read_i8 (negative offset)
    .{ .argument = "05", .code = "R_LIST_BOUNDS", .at = "probe.selka:31:16", .library = "bytes::read_u16_be" }, // bytes.read_u16_be (width past the end)
    .{ .argument = "06", .code = "R_LIST_BOUNDS", .at = "probe.selka:35:16", .library = "bytes::read_u32_le" }, // bytes.read_u32_le (width past the end)
    .{ .argument = "07", .code = "R_LIST_BOUNDS", .at = "probe.selka:39:16", .library = "bytes::read_i64_le" }, // bytes.read_i64_le (width past the end)
    .{ .argument = "08", .code = "R_LIST_BOUNDS", .at = "probe.selka:43:16", .library = "bytes::read_f64_le" }, // bytes.read_f64_le (width past the end)
    .{ .argument = "09", .code = "R_EMPTY_SEPARATOR", .at = "probe.selka:47:16", .library = "bytes::replace" }, // bytes.replace (empty old)
    .{ .argument = "10", .code = "R_OVERFLOW", .at = "probe.selka:52:5", .library = "dicts::add[str]" }, // dicts.add (overflow)
    .{ .argument = "11", .code = "R_ASSERT", .at = "probe.selka:58:16", .library = "spans::file_text" }, // spans.file_text (unknown file)
    .{ .argument = "12", .code = "R_ASSERT", .at = "probe.selka:63:16", .library = "spans::file_name" }, // spans.file_name (unknown file)
    .{ .argument = "13", .code = "R_ASSERT", .at = "probe.selka:68:12", .library = "spans::file_text" }, // spans.whole (unknown file)
    .{ .argument = "14", .code = "R_ASSERT", .at = "probe.selka:72:12", .library = "spans::of" }, // spans.of (negative start)
    .{ .argument = "15", .code = "R_ASSERT", .at = "probe.selka:76:12", .library = "spans::between" }, // spans.between (stop before start)
    .{ .argument = "16", .code = "R_ASSERT", .at = "probe.selka:80:12", .library = "spans::empty_at" }, // spans.empty_at (negative start)
    .{ .argument = "17", .code = "R_ASSERT", .at = "probe.selka:88:16", .library = "spans::text" }, // spans.text (span past its source)
    .{ .argument = "18", .code = "R_ASSERT", .at = "probe.selka:93:12", .library = "spans::sub" }, // spans.sub (outside its span)
    .{ .argument = "19", .code = "R_ASSERT", .at = "probe.selka:98:12", .library = "spans::join" }, // spans.join (two files)
    .{ .argument = "20", .code = "R_ASSERT", .at = "probe.selka:106:12", .library = "spans::hash" }, // spans.hash (span past its source)
    .{ .argument = "21", .code = "R_ASSERT", .at = "probe.selka:113:16", .library = "symbols::name" }, // symbols.name (symbol of another table)
    .{ .argument = "22", .code = "R_LIST_BOUNDS", .at = "probe.selka:118:9", .library = "byte_builder::append_range" }, // byte_builder.append_range (negative start)
    .{ .argument = "23", .code = "R_DIVISION_BY_ZERO", .at = "probe.selka:127:18", .library = null }, // sort.sort_by_key (the program's key traps)
};

const program =
    \\import strings
    \\import bytes
    \\import dicts
    \\import spans
    \\import symbols
    \\import byte_builder
    \\import sort
    \\
    \\
    \\func case_00() -> int:
    \\    return strings.find("éx", "x", 1).unwrap_or(-1)
    \\
    \\
    \\func case_01() -> int:
    \\    return strings.find("abc", "x", -1).unwrap_or(-1)
    \\
    \\
    \\func case_02() -> int:
    \\    return strings.rfind("éx", "x", 0, 1).unwrap_or(-1)
    \\
    \\
    \\func case_03() -> int:
    \\    return int(bytes.read_u8(b"ab", 5))
    \\
    \\
    \\func case_04() -> int:
    \\    return int(bytes.read_i8(b"ab", -1))
    \\
    \\
    \\func case_05() -> int:
    \\    return int(bytes.read_u16_be(b"ab", 1))
    \\
    \\
    \\func case_06() -> int:
    \\    return int(bytes.read_u32_le(b"abc", 0))
    \\
    \\
    \\func case_07() -> int:
    \\    return int(bytes.read_i64_le(b"abc", 0))
    \\
    \\
    \\func case_08() -> int:
    \\    return int(bytes.read_f64_le(b"abc", 0))
    \\
    \\
    \\func case_09() -> int:
    \\    return len(bytes.replace(b"ab", b"", b"x"))
    \\
    \\
    \\func case_10() -> int:
    \\    mut d: dict[str, int] = {"a": 9223372036854775807}
    \\    dicts.add(mut d, "a", 1)
    \\    return d["a"]
    \\
    \\
    \\func case_11() -> int:
    \\    const s = spans.create()
    \\    return len(spans.file_text(s, 3))
    \\
    \\
    \\func case_12() -> int:
    \\    const s = spans.create()
    \\    return len(spans.file_name(s, 3))
    \\
    \\
    \\func case_13() -> int:
    \\    const s = spans.create()
    \\    return spans.whole(s, 3).length
    \\
    \\
    \\func case_14() -> int:
    \\    return spans.of(0, -1, 2).length
    \\
    \\
    \\func case_15() -> int:
    \\    return spans.between(0, 5, 2).length
    \\
    \\
    \\func case_16() -> int:
    \\    return spans.empty_at(0, -1).length
    \\
    \\
    \\func case_17() -> int:
    \\    mut s = spans.create()
    \\    _ = spans.add(mut s, "a", b"ab")
    \\    mut t = spans.create()
    \\    const g = spans.add(mut t, "b", b"abcdef")
    \\    return len(spans.text(s, spans.whole(t, g)))
    \\
    \\
    \\func case_18() -> int:
    \\    const sp = spans.of(0, 0, 2)
    \\    return spans.sub(sp, 1, 5).length
    \\
    \\
    \\func case_19() -> int:
    \\    const a = spans.of(0, 0, 1)
    \\    return spans.join(a, spans.of(1, 0, 1)).length
    \\
    \\
    \\func case_20() -> int:
    \\    mut s = spans.create()
    \\    _ = spans.add(mut s, "a", b"ab")
    \\    mut t = spans.create()
    \\    const g = spans.add(mut t, "b", b"abcdef")
    \\    return spans.hash(s, spans.whole(t, g))
    \\
    \\
    \\func case_21() -> int:
    \\    mut a = symbols.create()
    \\    const x = symbols.intern(mut a, b"x")
    \\    const b = symbols.create()
    \\    return len(symbols.name(b, x))
    \\
    \\
    \\func case_22() -> int:
    \\    mut b = byte_builder.create()
    \\    _ = byte_builder.append_range(mut b, b"ab", -1, 1)
    \\    return 0
    \\
    \\
    \\func case_23() -> int:
    \\    return sort.sort_by_key([1, 2], key_of)[0]
    \\
    \\
    \\func key_of(value: int) -> int:
    \\    return value // 0
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    if args[0] == "00":
    \\        print(out, case_00())
    \\    if args[0] == "01":
    \\        print(out, case_01())
    \\    if args[0] == "02":
    \\        print(out, case_02())
    \\    if args[0] == "03":
    \\        print(out, case_03())
    \\    if args[0] == "04":
    \\        print(out, case_04())
    \\    if args[0] == "05":
    \\        print(out, case_05())
    \\    if args[0] == "06":
    \\        print(out, case_06())
    \\    if args[0] == "07":
    \\        print(out, case_07())
    \\    if args[0] == "08":
    \\        print(out, case_08())
    \\    if args[0] == "09":
    \\        print(out, case_09())
    \\    if args[0] == "10":
    \\        print(out, case_10())
    \\    if args[0] == "11":
    \\        print(out, case_11())
    \\    if args[0] == "12":
    \\        print(out, case_12())
    \\    if args[0] == "13":
    \\        print(out, case_13())
    \\    if args[0] == "14":
    \\        print(out, case_14())
    \\    if args[0] == "15":
    \\        print(out, case_15())
    \\    if args[0] == "16":
    \\        print(out, case_16())
    \\    if args[0] == "17":
    \\        print(out, case_17())
    \\    if args[0] == "18":
    \\        print(out, case_18())
    \\    if args[0] == "19":
    \\        print(out, case_19())
    \\    if args[0] == "20":
    \\        print(out, case_20())
    \\    if args[0] == "21":
    \\        print(out, case_21())
    \\    if args[0] == "22":
    \\        print(out, case_22())
    \\    if args[0] == "23":
    \\        print(out, case_23())
    \\    return 0
    \\
;

/// Build `probe.selka` in `dir` with `flags` and return the executable's path.
fn build(dir: std.Io.Dir, root: []const u8, output: []const u8, flags: []const []const u8) ![]const u8 {
    const allocator = testing.allocator;
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), allocator);
    defer allocator.free(compiler);
    const executable = try std.fs.path.join(allocator, &.{ root, output });
    errdefer allocator.free(executable);
    const cache = try std.fmt.allocPrint(allocator, "--cache-dir={s}/.cache", .{root});
    defer allocator.free(cache);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ compiler, "build", "probe.selka", "-o", executable, cache });
    try argv.appendSlice(allocator, flags);
    const built = try std.process.run(allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir } });
    defer allocator.free(built.stdout);
    defer allocator.free(built.stderr);
    errdefer std.debug.print("build failed:\n{s}\n", .{built.stderr});
    try testing.expect(built.term == .exited and built.term.exited == 0);
    return executable;
}

/// The location at the start of a trap report's first line, `path:line:column`.
fn firstLocation(stderr: []const u8) []const u8 {
    const line = stderr[0 .. std.mem.indexOfScalar(u8, stderr, '\n') orelse stderr.len];
    return line[0 .. std.mem.indexOf(u8, line, ": error[") orelse 0];
}

/// Run one case and check that its report leads to the program's call.
fn expectCase(dir: std.Io.Dir, executable: []const u8, case: Case) !void {
    const allocator = testing.allocator;
    const ran = try std.process.run(allocator, testing.io, .{ .argv = &.{ executable, case.argument }, .cwd = .{ .dir = dir } });
    defer allocator.free(ran.stdout);
    defer allocator.free(ran.stderr);
    errdefer std.debug.print("library trap case {s} reported:\n{s}\n", .{ case.argument, ran.stderr });
    try testing.expect(ran.term == .exited and ran.term.exited == 1);
    try testing.expectEqualStrings(case.at, firstLocation(ran.stderr));
    const code = try std.fmt.allocPrint(allocator, ": error[{s}]: ", .{case.code});
    defer allocator.free(code);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, code) != null);
    var lines = std.mem.splitScalar(u8, ran.stderr, '\n');
    _ = lines.next();
    const first_frame = lines.next() orelse return error.TestUnexpectedResult;
    if (case.library) |library| {
        const expected = try std.fmt.allocPrint(allocator, "  in {s} at @stdlib/", .{library});
        defer allocator.free(expected);
        try testing.expect(std.mem.startsWith(u8, first_frame, expected));
    }
    // The first frame outside the library is the call the first line names; `main` follows.
    var frame = first_frame;
    while (std.mem.indexOf(u8, frame, " at @stdlib/") != null) frame = lines.next() orelse return error.TestUnexpectedResult;
    try testing.expect(std.mem.startsWith(u8, frame, "  in probe::"));
    try testing.expect(std.mem.endsWith(u8, frame, case.at));
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "\n  in probe::main at probe.selka:") != null);
}

/// Build the program with `flags` and run every case; answers how many ran.
fn checkAll(flags: []const []const u8) !usize {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "probe.selka", .data = program });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const executable = try build(temp.dir, root, "probe", flags);
    defer testing.allocator.free(executable);
    for (cases) |case| try expectCase(temp.dir, executable, case);
    return cases.len;
}

test "a trap inside a library function leads with the program's call and keeps the library frame as context" {
    try testing.expectEqual(cases.len, try checkAll(&.{}));
}

test "a trap inside a library function leads with the program's call in a release build too" {
    try requireRelease();
    try testing.expectEqual(cases.len, try checkAll(&.{"--release"}));
}

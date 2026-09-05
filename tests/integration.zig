//! Spawn the selected-mode compiler binary; fixtures assert the public CLI contract.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;

fn invoke(command: []const u8, text: []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    return invokeOptions(command, text, &.{}, expected_status, expected_stdout, stderr_part);
}

fn invokeOptions(command: []const u8, text: []const u8, options: []const []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    const outcome = try runFixture(command, text, options);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, outcome.term);
    try testing.expectEqualStrings(expected_stdout, outcome.stdout);
    if (stderr_part.len == 0) try testing.expectEqualStrings("", outcome.stderr) else try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
}

fn runFixture(command: []const u8, text: []const u8, options: []const []const u8) !std.process.RunResult {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, command, path });
    try args.appendSlice(testing.allocator, options);
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

test "CLI run and check success" {
    try invoke("run", @embedFile("fixtures/arithmetic.my"), 0, "7\n", "");
    try invoke("check", @embedFile("fixtures/arithmetic.my"), 0, "", "");
}

test "CLI dumps actual instructions" {
    try invoke("dump-bytecode", @embedFile("fixtures/arithmetic.my"), 0, @embedFile("fixtures/arithmetic.dump"), "");
}

test "CLI distinguishes source errors runtime traps and usage" {
    try invoke("check", "fn main() -> i64 { return 1 + ; }", 1, "", "error[E_EXPRESSION]");
    try invoke("check", "fn main() -> i64 { return 9223372036854775807 + 1; }", 0, "", "");
    try invoke("run", "fn main() -> i64 { return 9223372036854775807 + 1; }", 1, "", "error[R_OVERFLOW]");
    try invoke("unknown", "", 2, "", "usage:");
}

test "CLI missing arguments and missing files are host or usage failures" {
    const no_args = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{compiler_path} });
    defer testing.allocator.free(no_args.stdout);
    defer testing.allocator.free(no_args.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, no_args.term);
    try testing.expectEqualStrings("", no_args.stdout);
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const absolute_compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(absolute_compiler);
    const absent = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ absolute_compiler, "run", "missing.my" },
        .cwd = .{ .dir = temp.dir },
    });
    defer testing.allocator.free(absent.stdout);
    defer testing.allocator.free(absent.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, absent.term);
    try testing.expectEqualStrings("", absent.stdout);
    try testing.expect(std.mem.indexOf(u8, absent.stderr, "FileNotFound") != null);
}

test "CLI binding warnings do not alter status or result output" {
    const text = "fn main() -> i64 { let mut x = 7; return x; }";
    try invoke("run", text, 0, "7\n", "warning[W_UNNECESSARY_MUT]");
    try invoke("check", text, 0, "", "warning[W_UNNECESSARY_MUT]");
    try invoke("run", "fn main() -> i64 { let unused = 9223372036854775807 + 1; return 7; }", 1, "", "error[R_OVERFLOW]");
    try invoke("run", "fn main() -> i64 { return -9223372036854775808; }", 0, "-9223372036854775808\n", "");
    try invoke("check", "fn main() -> i64 { let mut x = true; x = 1; return 7; }", 1, "", "error[E_TYPE]");
}

test "CLI step budgets count dispatch and reject invalid options" {
    const text = "fn main() -> i64 { return 1; }";
    try invokeOptions("run", text, &.{"--max-steps=2"}, 0, "1\n", "");
    try invokeOptions("run", text, &.{"--max-steps=1"}, 1, "", "error[R_STEP_LIMIT]");
    try invokeOptions("run", "fn main() -> i64 { while true {} return 1; }", &.{"--max-steps=100"}, 1, "", "error[R_STEP_LIMIT]");
    for ([_][]const u8{ "--max-steps=0", "--max-steps=-1", "--max-steps=+1", "--max-steps=", "--max-steps=abc", "--max-steps=18446744073709551616", "--unknown=1" }) |option| {
        try invokeOptions("run", text, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("run", text, &.{ "--max-steps=2", "--max-steps=3" }, 2, "", "usage:");
    try invokeOptions("check", text, &.{"--max-steps=2"}, 2, "", "usage:");
    try invokeOptions("dump-bytecode", text, &.{"--max-steps=2"}, 2, "", "usage:");
}

test "CLI executes control flow and preserves discarded traps" {
    try invoke("run", "fn main() -> i64 { let mut sum = 0; let mut i = 0; while i < 100 { sum += i; i += 1; } return sum; }", 0, "4950\n", "");
    try invoke("run", "fn main() -> i64 { if false && 1 / 0 == 0 { return 1; } else { return 7; } }", 0, "7\n", "");
    try invoke("run", "fn main() -> i64 { discard 1 / 0; return 7; }", 1, "", "error[R_DIVISION_BY_ZERO]");
    try invoke("check", "fn main() -> i64 { while true { return 7; } }", 1, "", "error[E_MISSING_RETURN]");
}

test "CLI executes the exact plan acceptance programs and recursive functions" {
    try invoke("run", @embedFile("fixtures/sum.my"), 0, "4950\n", "");
    try invoke("run", @embedFile("fixtures/gcd.my"), 0, "6\n", "");
    try invoke("run", "fn fact(n: i64) -> i64 { if n <= 1 { return 1; } return n * fact(n - 1); } fn main() -> i64 { return fact(10); }", 0, "3628800\n", "");
    try invoke("run", "fn main() -> i64 { return 1 + add(add(2, 3), add(4, 5)); } fn add(a: i64, b: i64) -> i64 { return a + b; }", 0, "15\n", "");
    try invoke("run", "fn main() -> i64 { return bad(); } fn bad() -> i64 { return 1 / 0; }", 1, "", "in main at");
}

test "CLI frame budgets count main and reject invalid overrides" {
    const text = "fn main() -> i64 { return f(); } fn f() -> i64 { return 7; }";
    try invokeOptions("run", text, &.{"--max-frames=2"}, 0, "7\n", "");
    try invokeOptions("run", text, &.{"--max-frames=1"}, 1, "", "error[R_FRAME_LIMIT]");
    try invokeOptions("run", text, &.{ "--max-frames=2", "--max-steps=4" }, 0, "7\n", "");
    for ([_][]const u8{ "--max-frames=0", "--max-frames=-1", "--max-frames=+1", "--max-frames=", "--max-frames=abc", "--max-frames=18446744073709551616" }) |option| {
        try invokeOptions("run", text, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("run", text, &.{ "--max-frames=2", "--max-frames=3" }, 2, "", "usage:");
    try invokeOptions("check", text, &.{"--max-frames=2"}, 2, "", "usage:");
    try invokeOptions("dump-bytecode", text, &.{"--max-frames=2"}, 2, "", "usage:");
}

test "all commands preserve stdout and deterministic advisory stderr" {
    const source = @embedFile("fixtures/warnings.my");
    const commands = [_][]const u8{ "check", "run", "dump-bytecode" };
    const outputs = [_][]const u8{ "", "7\n", @embedFile("fixtures/warnings.dump") };
    for (commands, outputs) |command, expected| {
        const outcome = try runFixture(command, source, &.{});
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
        try testing.expectEqualStrings(expected, outcome.stdout);
        const first = std.mem.indexOf(u8, outcome.stderr, ":2:13: warning[W_UNNECESSARY_MUT]") orelse return error.MissingWarning;
        const second = std.mem.indexOf(u8, outcome.stderr, ":2:13: warning[W_UNUSED_BINDING]") orelse return error.MissingWarning;
        try testing.expect(first < second);
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, outcome.stderr, "warning["));
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "discard") != null);
    }
}

test "all commands reject invalid programs before execution and locate runtime traps" {
    for ([_][]const u8{ "check", "run", "dump-bytecode" }) |command| {
        try invoke(command, @embedFile("fixtures/rejected.my"), 1, "", ":2:12: error[E_UNKNOWN_NAME]");
        try invoke(command, "", 1, "", "error[E_MAIN]");
        try invoke(command, "fn main() -> bool { return true; }", 1, "", "error[E_TYPE]");
    }
    try invoke("check", @embedFile("fixtures/trap.my"), 0, "", "");
    try invoke("run", @embedFile("fixtures/trap.my"), 1, "", ":2:15: error[R_DIVISION_BY_ZERO]");
}

test "oversized source is a host resource failure with no result output" {
    const text = try testing.allocator.alloc(u8, 16 * 1024 * 1024 + 1);
    defer testing.allocator.free(text);
    @memset(text, ' ');
    try invoke("run", text, 2, "", "host failure:");
}

test "duplicate discovery is separate advisory analysis with explicit options" {
    const source = "fn a(n: i64) -> i64 { return n * 2 + 1; } fn b(x: i64) -> i64 { return x * 2 + 1; } fn main() -> i64 { return 7; }";
    const outcome = try runFixture("discover-duplicates", source, &.{ "--min-nodes=1", "--population=reference", "--timings" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "1 candidate groups") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "population=reference") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "discovery_ns=") != null);
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 0, "7\n", "");
    try invoke("discover-duplicates", "fn main() -> i64 { return unknown; }", 1, "", "error[E_UNKNOWN_NAME]");
    for ([_][]const u8{ "--min-nodes=0", "--min-nodes=", "--min-nodes=-1", "--population=unknown", "--max-steps=10" }) |option| {
        try invokeOptions("discover-duplicates", source, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("discover-duplicates", source, &.{ "--min-nodes=1", "--min-nodes=2" }, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--min-nodes=1"}, 2, "", "usage:");
}

test "CLI checks runs and dumps records and declared complete conversions" {
    try invoke("run", @embedFile("fixtures/records.my"), 0, "12\n", "");
    try invoke("run", @embedFile("fixtures/conversions.my"), 0, "11\n", "");
    try invoke("check", @embedFile("fixtures/conversions.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/conversions.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "conversion function to_view(source: Source) -> View") != null);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "MAKE_RECORD") != null);
    const incomplete = "struct Source { x: i64, added: bool } struct View { y: i64 } conversion fn convert(src: Source) -> View { return new View { y: src.x }; } fn main() -> i64 { return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, incomplete, 1, "", "error[E_INCOMPLETE_CONVERSION]");
    }
}

test "CLI preserves integer width bounds and explicit casts" {
    try invoke("run", @embedFile("fixtures/integers.my"), 0, "6148914691236516950\n", "");
    try invoke("check", "fn main() -> i64 { discard cast<u8>(256); return 0; }", 0, "", "");
    try invoke("run", "fn main() -> i64 { discard cast<u8>(256); return 0; }", 1, "", "error[R_OVERFLOW]");
    try invoke("run", "fn main() -> i64 { discard 255u8 + 1u8; return 0; }", 1, "", "error[R_OVERFLOW]");
    try invoke("check", "fn main() -> i64 { discard 256u8; return 0; }", 1, "", "error[E_INTEGER_RANGE]");
    try invoke("check", "fn main() -> u8 { return 0u8; }", 1, "", "error[E_TYPE]");
}

test "CLI checks array schemas dumps indexing and reports bounds traps" {
    try invoke("run", @embedFile("fixtures/arrays.my"), 0, "44\n", "");
    try invoke("check", @embedFile("fixtures/arrays.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/arrays.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "array [3]i64", "GET_INDEX [3]i64", "REPLACE_INDEX [3]i64", "ARRAY_LENGTH [3]i64" }) |instruction| {
        try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    }
    const invalid = "fn main() -> i64 { discard new [2]i64 [1]; return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, invalid, 1, "", "error[E_ARRAY_ARITY]");
    }
    const bounds = "fn main() -> i64 {\n    return new [1]i64 [7][-1];\n}";
    try invoke("check", bounds, 0, "", "");
    try invoke("run", bounds, 1, "", ":2:12: error[R_INDEX_BOUNDS]");
    try invoke("run", "fn main() -> i64 { discard replace(new [1]u8 [7u8], 18446744073709551615u64, 8u8); return 0; }", 1, "", "error[R_INDEX_BOUNDS]");
}

test "CLI checks domain privacy unit mismatches and qualified factory execution" {
    try invoke("run", @embedFile("fixtures/domains.my"), 0, "1003\n", "");
    try invoke("check", @embedFile("fixtures/domains.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/domains.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "domain Millimeters", "private function Millimeters.raw", "WRAP_DOMAIN Millimeters", "UNWRAP_DOMAIN Seconds" }) |instruction| {
        try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    }
    const private = "domain D: i64 { private fn raw(n: i64) -> D { return wrap<D>(n); } } fn main() -> i64 { discard D.raw(1); return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, private, 1, "", "error[E_PRIVATE_FUNCTION]");
    }
    try invoke("check", "domain D: i64 {} fn main() -> i64 { discard wrap<D>(1); return 0; }", 1, "", "error[E_PRIVATE_DOMAIN]");
    try invoke("check", "domain Seconds: i64 { fn from(n: i64) -> Seconds { return wrap<Seconds>(n); } } domain Millimeters: i64 {} fn distance(n: Millimeters) -> i64 { discard n; return 0; } fn main() -> i64 { return distance(Seconds.from(1)); }", 1, "", "expected Millimeters, found Seconds");
}

test "CLI executes variants dumps dispatch and rejects newly incomplete matches" {
    try invoke("run", @embedFile("fixtures/variants.my"), 0, "24\n", "");
    try invoke("check", @embedFile("fixtures/variants.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/variants.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "enum Color", "union Shape", "MAKE_VARIANT Shape.point", "SWITCH_VARIANT Shape" }) |instruction| try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    const added = "enum Color { red, green, added } fn main() -> i64 { match new Color.red { Color.red => { return 1; }, Color.green => { return 2; } } }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "match does not handle variant `added`");
    try invoke("check", "union U { value: i64, empty } fn main() -> i64 { discard new U.value(true); return 0; }", 1, "", "error[E_TYPE]");
    try invoke("run", "union U { value: i64 } fn main() -> i64 { match new U.value(1 / 0) { U.value(discard) => { return 0; } } }", 1, "", "error[R_DIVISION_BY_ZERO]");
}

test "CLI executes complete enum tables and rejects missing mappings in every command" {
    try invoke("run", @embedFile("fixtures/tables.my"), 0, "1407\n", "");
    try invoke("check", @embedFile("fixtures/tables.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/tables.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "table [Status]u16", "GET_INDEX [Status]u16", "REPLACE_INDEX [Status]u16" }) |instruction| try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    const added = "enum Key { old, added } fn main() -> i64 { return new [Key]i64 { old: 7 }[new Key.old]; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "missing initializer for key `added`");
    try invoke("check", "enum Key { a } fn main() -> i64 { return new [Key]i64 { a: 7 }[0]; }", 1, "", "expected Key, found i64");
    try invoke("check", "enum Key { a } fn main() -> i64 { discard new [Key]i64 [7]; return 0; }", 1, "", "error[E_TABLE_CONSTRUCTION]");
}

test "CLI checks scoped borrows runs early cleanup and locates alias errors" {
    try invoke("run", @embedFile("fixtures/references.my"), 0, "23\n", "");
    try invoke("check", @embedFile("fixtures/references.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/references.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "BEGIN_BORROW", "END_BORROW", "READ_REF", "WRITE_REF" }) |instruction| try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    const conflict = "fn main() -> i64 { let mut x = 1; borrow mut x as r { return x; } }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, conflict, 1, "", "error[E_BORROW_CONFLICT]");
    try invoke("check", "fn main() -> i64 { let x = 1; borrow x as r {} return read_ref(r); }", 1, "", "error[E_REFERENCE_SCOPE]");
    try invoke("run", "fn main() -> i64 { let mut x = 1; borrow mut x as r { write_ref(r, 1 / 0); } return x; }", 1, "", "error[R_DIVISION_BY_ZERO]");
}

test "CLI runs reference parameter helpers and rejects invalid call loans" {
    const source = @embedFile("fixtures/reference-parameters.my");
    try invoke("run", source, 0, "19\n", "");
    try invoke("check", source, 0, "", "");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "CALL_REFS") != null);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "counter: &mut Counter") != null);
    const conflict = "fn f(a: &mut i64, b: &mut i64) -> i64 { return read_ref(a) + read_ref(b); } fn main() -> i64 { let mut x = 0; borrow mut x as r { return f(r, r); } }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, conflict, 1, "", "error[E_BORROW_CONFLICT]");
    try invoke("run", "fn fail(r: &mut i64) -> i64 { write_ref(r, 1 / 0); return 0; } fn main() -> i64 { let mut x = 0; borrow mut x as r { return fail(r); } }", 1, "", "error[R_DIVISION_BY_ZERO]");
}

test "CLI runs bounded slice helpers and locates bounds and alias failures" {
    const source = @embedFile("fixtures/slices.my");
    try invoke("run", source, 0, "13\n", "");
    try invoke("check", source, 0, "", "");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "BEGIN_SLICE", "READ_SLICE", "WRITE_SLICE", "LEN_SLICE", "values: &mut []i64" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid = "fn main() -> i64 { let mut a = new [1]i64 [1]; borrow mut a[0..1] as s { return a[0]; } }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_BORROW_CONFLICT]");
    try invoke("run", "fn main() -> i64 { let a = new [1]i64 [1]; borrow a[0..1] as s { return read_slice(s, 1); } }", 1, "", "error[R_SLICE_BOUNDS]");
}

test "CLI runs returned views and rejects escaping local references" {
    const source = @embedFile("fixtures/returned-references.my");
    try invoke("run", source, 0, "20\n", "");
    try invoke("check", source, 0, "", "");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "CALL_BORROW", "CAPTURE_REF", "RETURN_REF", "from values" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const escape = "fn bad(input: &i64) -> &i64 from input { let local = 7; borrow local as r { return r; } } fn main() -> i64 { return 0; }";
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, escape, 1, "", "error[E_RETURN_LIFETIME]");
    try invoke("run", "fn one(s: &[]i64) -> &[]i64 from s { borrow s[0..1] as r { return r; } } fn main() -> i64 { let a = new [2]i64 [1, 2]; borrow a[0..2] as s { borrow one(s) as r { return read_slice(r, 1); } } }", 1, "", "error[R_SLICE_BOUNDS]");
}

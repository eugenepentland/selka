//! The stand-in count of W3, step 1 (`selka template-stand-ins`, `src/core/template_stand_ins_command.zig`): a developer
//! command that tries every template with a scalar, a text, a record, a list and a move-only stand-in and prints what the
//! ownership pass would say. It refuses nothing. `check` itself judges every generic body at its declaration (W3 step 2).
const std = @import("std");
const testing = std.testing;

/// What one command printed, and how it ended.
const Outcome = struct {
    code: u8,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: Outcome) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

/// `selka ARGS...` run in a fresh directory holding `files` (path and text pairs), with a private environment.
fn ran(files: []const [2][]const u8, args: []const []const u8) !Outcome {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    for (files) |file| try temporary.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, compiler);
    try argv.appendSlice(testing.allocator, args);
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = argv.items,
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    return .{ .code = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .stdout = result.stdout, .stderr = result.stderr };
}

/// The three probes of the language-goals audit (`experiments/language-goals-audit-20261111/probes`).
const generic_int =
    \\record Box[T]:
    \\    items: T[]
    \\
    \\func first[T](xs: T[]) -> T:
    \\    const head = xs[0]
    \\    return head
    \\
    \\func keep[T](xs: T[], x: T) -> T[]:
    \\    mut out: T[] = []
    \\    append(mut out, x)
    \\    return out
    \\
    \\func main() -> int:
    \\    const a = first([1, 2, 3])
    \\    const b = keep([1], 5)
    \\    return a + len(b)
    \\
;
const generic_str =
    \\func first[T](xs: T[]) -> T:
    \\    const head = xs[0]
    \\    return head
    \\
    \\func keep[T](xs: T[], x: T) -> T[]:
    \\    mut out: T[] = []
    \\    append(mut out, x)
    \\    return out
    \\
    \\func main() -> int:
    \\    const a = first(["a", "b"])
    \\    const b = keep(["x"], "y")
    \\    return len(a) + len(b)
    \\
;
const generic_marked =
    \\func first[T](xs: T[]) -> T:
    \\    return copy(xs[0])
    \\
    \\func keep[T](own x: T) -> T[]:
    \\    mut out: T[] = []
    \\    append(mut out, own x)
    \\    return out
    \\
    \\func main() -> int:
    \\    const a = first(["a", "b"])
    \\    const b = keep("y")
    \\    const c = first([1, 2])
    \\    const d = keep(5)
    \\    return len(a) + len(b) + c + len(d)
    \\
;
/// A program that calls two standard-library templates with `int`.
const library =
    \\import lists
    \\import sets
    \\
    \\
    \\func main() -> int:
    \\    mut s: set[int] = set()
    \\    sets.add(mut s, 1)
    \\    mut xs = [3, 1, 2]
    \\    lists.reverse(mut xs)
    \\    return len(s) + xs[0]
    \\
;

/// `check` of one file with a fresh cache, its status and its whole standard error (stdout must stay empty).
fn checked(name: []const u8, text: []const u8) !Outcome {
    return ran(&.{.{ name, text }}, &.{ "check", name, "--cache-dir", "cache" });
}

// W3 step 2: `check` judges every generic body at its declaration, so `generic_int.selka`'s two bodies, which only its `int`
// instances reached before, are refused at their declarations as `generic_str.selka`'s are; the strict bodies and the library pass.
test "W3 check refuses the probes' generic bodies at their declaration and accepts the strict bodies and a library program" {
    const int_run = try checked("generic_int.selka", generic_int);
    defer int_run.deinit();
    try testing.expectEqual(@as(u8, 1), int_run.code);
    try testing.expectEqualStrings("", int_run.stdout);
    try testing.expectEqualStrings(
        \\generic_int.selka:4:6: error[E_BORROW_UNDECLARED]: the body of `first` is refused when `T` is a text, a record with a managed field or a list; a generic body is judged at its declaration for every kind of type argument its bounds admit
        \\  func first[T](xs: T[]) -> T:
        \\       ^
        \\  note: ownership rule R4
        \\  note: generic_int.selka:6:12: `head` is lent by the plain parameter `xs`, and the returned value would keep it after the call returns; declare the result `from xs`: no caller in the program keeps the result, so none needs a copy
        \\generic_int.selka:8:6: error[E_SINGLE_OWNER_BORROW]: the body of `keep` is refused when `T` is a text, a record with a managed field or a list; a generic body is judged at its declaration for every kind of type argument its bounds admit
        \\  func keep[T](xs: T[], x: T) -> T[]:
        \\       ^
        \\  note: ownership rule R1
        \\  note: generic_int.selka:10:21: a bare `x` only lends the plain parameter `x`, and the list `out` needs its own value; write `copy(x)` to keep both
        \\  note: generic_int.selka:11:5: `out` owns its elements because this line returns it, so the earlier line needs `copy(...)` or `own`
        \\
    , int_run.stderr);
    const str_run = try checked("generic_str.selka", generic_str);
    defer str_run.deinit();
    try testing.expectEqual(@as(u8, 1), str_run.code);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, str_run.stderr, "error["));
    try testing.expect(std.mem.indexOf(u8, str_run.stderr, "generic_str.selka:1:6: error[E_BORROW_UNDECLARED]: the body of `first` is refused when `T` is a text") != null);
    const marked_run = try checked("generic_marked.selka", generic_marked);
    defer marked_run.deinit();
    try testing.expectEqual(@as(u8, 0), marked_run.code);
    try testing.expectEqualStrings("check: ok (1 module, 0 cached)\n", marked_run.stderr);
    const library_run = try checked("library.selka", library);
    defer library_run.deinit();
    try testing.expectEqual(@as(u8, 0), library_run.code);
    try testing.expectEqualStrings("", library_run.stdout);
    try testing.expectEqualStrings("check: ok (3 modules, 0 cached)\n", library_run.stderr);
}

/// Whether `report` holds `line` as one whole line.
fn holdsLine(report: []const u8, line: []const u8) bool {
    var lines = std.mem.splitScalar(u8, report, '\n');
    while (lines.next()) |each| if (std.mem.eql(u8, each, line)) return true;
    return false;
}

test "W3 the stand-in count reports generic_str's first and keep refused for str and accepted for int" {
    const run = try ran(&.{.{ "generic_str.selka", generic_str }}, &.{ "template-stand-ins", "generic_str.selka" });
    defer run.deinit();
    try testing.expectEqual(@as(u8, 0), run.code);
    try testing.expectEqualStrings("", run.stderr);
    try testing.expect(std.mem.startsWith(u8, run.stdout, "template-stand-ins-v1 int=i64 str=str record=tuple<str,i64> list=List<i64> move-only=-\n"));
    try testing.expect(holdsLine(run.stdout, "generic_str.selka:1:6 first[int] accepted"));
    try testing.expect(holdsLine(run.stdout, "generic_str.selka:1:6 first[str] refused E_BORROW_UNDECLARED generic_str.selka:3:12 (1) fix=\" from xs\""));
    try testing.expect(holdsLine(run.stdout, "generic_str.selka:5:6 keep[int] accepted"));
    try testing.expect(holdsLine(run.stdout, "generic_str.selka:5:6 keep[str] refused E_SINGLE_OWNER_BORROW generic_str.selka:7:21 (1) fix=\"copy(\",\")\""));
    try testing.expect(holdsLine(run.stdout, "generic_str.selka:5:6 keep[move-only] skipped no such type in the program"));
    // The program's own instances, with the kind of each type argument.
    try testing.expect(holdsLine(run.stdout, "instance generic_str.selka:1:6 first[str] kinds=str"));
    try testing.expect(holdsLine(run.stdout, "totals: rows 10, accepted 2, refused 6, refused-in-check 0, skipped 2, other refused functions 0"));
}

test "W3 the stand-in count accepts generic_marked's bodies for every stand-in, and the probe's own check is unchanged" {
    const run = try ran(&.{.{ "generic_marked.selka", generic_marked }}, &.{ "template-stand-ins", "generic_marked.selka" });
    defer run.deinit();
    try testing.expectEqual(@as(u8, 0), run.code);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "] refused") == null);
    try testing.expect(holdsLine(run.stdout, "generic_marked.selka:1:6 first[record] accepted"));
    try testing.expect(holdsLine(run.stdout, "generic_marked.selka:4:6 keep[list] accepted"));
    try testing.expect(holdsLine(run.stdout, "totals: rows 10, accepted 8, refused 0, refused-in-check 0, skipped 2, other refused functions 0"));
}

/// Shapes beyond the probes: two type parameters where only some pairs refuse, a template that calls another, a `from`
/// result, a `mut` parameter of the generic type, a structural requirement, a constant length, and a body its own check
/// refuses for some stand-ins (`take` of a type with no default).
const shapes =
    \\record Item:
    \\    value: int
    \\
    \\func second[A, B](a: A, b: B) -> B:
    \\    return b
    \\
    \\func outer[T](xs: T[]) -> T:
    \\    return first_of(xs)
    \\
    \\func first_of[T](xs: T[]) -> T:
    \\    return xs[0]
    \\
    \\func borrowed[T](xs: T[]) -> T from xs:
    \\    return xs[0]
    \\
    \\func swap_in[T](mut slot: T, own next: T) -> Unit:
    \\    slot = own next
    \\
    \\func value_of[T: copy + field(value: int)](item: T) -> int:
    \\    return item.value
    \\
    \\func length[T, const N: u64](items: FixedArray[T, N]) -> int:
    \\    return int(N)
    \\
    \\func emptied[T](mut value: T) -> T:
    \\    return take(mut value)
    \\
    \\func main() -> int:
    \\    return value_of(Item(value=1))
    \\
;

test "W3 the stand-in count's shapes: pairs, a callee template, a from result, a mut parameter, structural, lengths, take" {
    const run = try ran(&.{.{ "shapes.selka", shapes }}, &.{ "template-stand-ins", "shapes.selka" });
    defer run.deinit();
    try testing.expectEqual(@as(u8, 0), run.code);
    // Only the pairs whose second argument is managed refuse the returned borrow.
    try testing.expect(holdsLine(run.stdout, "shapes.selka:4:6 second[str,int] accepted"));
    try testing.expect(holdsLine(run.stdout, "shapes.selka:4:6 second[int,str] refused E_BORROW_UNDECLARED shapes.selka:5:12 (1) fix=\" from b\""));
    // A template that returns another template's result is judged by the callee's signature: the refusal stays in the callee.
    try testing.expect(holdsLine(run.stdout, "shapes.selka:7:6 outer[list] accepted"));
    try testing.expect(holdsLine(run.stdout, "shapes.selka:10:6 first_of[list] refused E_BORROW_UNDECLARED shapes.selka:11:12 (1) fix=\" from xs\""));
    // A declared `from` result and an `own`/`mut` body are accepted for every stand-in.
    try testing.expect(holdsLine(run.stdout, "shapes.selka:13:6 borrowed[str] accepted"));
    try testing.expect(holdsLine(run.stdout, "shapes.selka:16:6 swap_in[record] accepted"));
    try testing.expect(holdsLine(run.stdout, "shapes.selka:19:6 value_of[int] skipped structural requirement"));
    try testing.expect(holdsLine(run.stdout, "shapes.selka:22:6 length[str,int] accepted"));
    try testing.expect(holdsLine(run.stdout, "shapes.selka:25:6 emptied[int] refused-in-check E_TAKE_TYPE shapes.selka:26:12"));
    try testing.expect(holdsLine(run.stdout, "shapes.selka:25:6 emptied[list] accepted"));
}

// spec-case: W3-SET-COMBINE-1
// W3 step 2, move 1: the lowering of the three set operations stored each kept key, borrowed from the walked operand, with
// a consuming write, so every call on a set of text was refused (`E_SINGLE_OWNER_OVERLAP`). The write copies the key now.
test "W3 sets.intersection, sets.difference and sets.symmetric_difference of text sets are accepted by check and run" {
    const text_sets =
        \\import sets
        \\
        \\
        \\func main() -> int:
        \\    mut left: set[str] = set()
        \\    sets.add(mut left, "a")
        \\    sets.add(mut left, "b")
        \\    mut right: set[str] = set()
        \\    sets.add(mut right, "b")
        \\    const both = sets.intersection(left, right)
        \\    const only = sets.difference(left, right)
        \\    const either = sets.symmetric_difference(left, right)
        \\    return len(both) * 100 + len(only) * 10 + len(either)
        \\
    ;
    const checked_run = try checked("text_sets.selka", text_sets);
    defer checked_run.deinit();
    try testing.expectEqual(@as(u8, 0), checked_run.code);
    try testing.expectEqualStrings("check: ok (2 modules, 0 cached)\n", checked_run.stderr);
    const ran_run = try ran(&.{.{ "text_sets.selka", text_sets }}, &.{ "run", "text_sets.selka", "--cache-dir", "cache" });
    defer ran_run.deinit();
    try testing.expectEqual(@as(u8, 111), ran_run.code);
}

// spec-case: W3-LIBRARY-JUDGMENT-1
// The gate's judgment of the standard library (W3 step 2): `check` skips the library's generic bodies, because the library is
// embedded in the compiler and is judged here once per compiler, with every stand-in the rule tries (a scalar, a text, a
// record with a managed field and a list for each type parameter alone, and every parameter the same managed kind) and more
// (the developer count also tries every pair of kinds and a resource). A library template any of them refuses fails the gate.
test "W3 gate: every generic body of the standard library is accepted for every stand-in the declaration rule tries" {
    const run = try ran(&.{}, &.{ "template-stand-ins", "--standard-library" });
    defer run.deinit();
    try testing.expectEqual(@as(u8, 0), run.code);
    try testing.expectEqualStrings("", run.stderr);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "] refused") == null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, ", refused 0, refused-in-check 0, skipped ") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "@stdlib/lists.selka:") != null);
}

/// A library whose template `keep_name` names a callee (`label`), a record (`Row`) and a bound, for the key tests below.
const judged_library =
    \\public record Row:
    \\    name: str
    \\
    \\
    \\public func label(rows: Row[]) -> str from rows:
    \\    return rows[0].name
    \\
    \\
    \\public func keep_name[T](value: T, rows: Row[]) -> str from rows:
    \\    # a comment
    \\    return label(rows)
    \\
;
const judged_main =
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    const rows = [lib.Row(name="a")]
    \\    return len(lib.keep_name(1, rows))
    \\
;

/// How many generic instances one `check --report` made (`instantiated_specializations.performed`), and whether it passed.
fn instancesMade(project_dir: std.Io.Dir, environment: *const std.process.Environ.Map) !struct { made: usize, passed: bool } {
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "check", "main.selka", "--cache-dir", "cache", "--report" },
        .cwd = .{ .dir = project_dir },
        .environ_map = environment,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    const at = std.mem.indexOf(u8, result.stderr, "\"instantiated_specializations\":") orelse return error.MissingCounter;
    const performed = std.mem.indexOfPos(u8, result.stderr, at, "\"performed\":") orelse return error.MissingCounter;
    var end = performed + "\"performed\":".len;
    while (end < result.stderr.len and std.ascii.isDigit(result.stderr[end])) end += 1;
    return .{ .made = try std.fmt.parseInt(usize, result.stderr[performed + "\"performed\":".len .. end], 10), .passed = result.term == .exited and result.term.exited == 0 };
}

/// The instances made by a cold check, a second check, and a check after `edit` replaced `from` with `to` in the library.
fn judgedAfter(from: []const u8, to: []const u8, verify: bool) ![3]usize {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = judged_library });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = judged_main });
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    // A Debug compiler judges one held proof in 64 again by default, chosen by the proof's digest, which the compiler's
    // identity is part of: left unset, a count here depended on which compiler was built. Each run says which it means.
    try environment.put("SELKA_ENGINE_VERIFY", if (verify) "1" else "0");
    const cold = try instancesMade(temporary.dir, &environment);
    const warm = try instancesMade(temporary.dir, &environment);
    const edited = try std.mem.replaceOwned(u8, testing.allocator, judged_library, from, to);
    defer testing.allocator.free(edited);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = edited });
    const after = try instancesMade(temporary.dir, &environment);
    try testing.expect(cold.passed and warm.passed);
    return .{ cold.made, warm.made, after.made };
}

// spec-case: W3-JUDGMENT-REUSE-1
// The judgment of `keep_name` at its declaration makes four instances (`int`, a text, a record, a list); a second check finds
// the judgment proven under its key (the stable key, the dependency context folded with the rule, the declaration's tokens)
// and makes none. Each test changes one thing the judgment can depend on and shows the template judged again.
test "W3 a template's judgment is reused while nothing it depends on changes" {
    try testing.expectEqual([3]usize{ 4, 0, 0 }, try judgedAfter("# a comment", "# a comment", false));
}

test "W3 a template is judged again when a callee loses its from contract" {
    try testing.expectEqual([3]usize{ 4, 0, 4 }, try judgedAfter("public func label(rows: Row[]) -> str from rows:\n    return rows[0].name", "public func label(rows: Row[]) -> str:\n    return copy(rows[0].name)", false));
}

test "W3 a template is judged again when a record it names gains a managed field" {
    try testing.expectEqual([3]usize{ 4, 0, 4 }, try judgedAfter("public record Row:\n    name: str\n", "public record Row:\n    name: str\n    tags: str[] = []\n", false));
}

test "W3 a template is judged again when its bound changes" {
    try testing.expectEqual([3]usize{ 4, 0, 4 }, try judgedAfter("keep_name[T](value", "keep_name[T: copy](value", false));
}

test "W3 a comment in a template's body keeps its judgment and one token judges it again" {
    // The comment keeps the three stand-ins' judgment; the one instance made is the program's own `keep_name[i64]`, whose
    // body is checked again because its source moved.
    try testing.expectEqual([3]usize{ 4, 0, 1 }, try judgedAfter("# a comment", "# another, longer comment", false));
    try testing.expectEqual([3]usize{ 4, 0, 4 }, try judgedAfter("    return label(rows)", "    return label(rows[0:1])", false));
}

test "W3 verify mode judges a held template again" {
    // After a comment edit the judgment is held (as the comment test shows), and verify mode judges it anyway.
    try testing.expectEqual([3]usize{ 4, 0, 4 }, try judgedAfter("# a comment", "# another, longer comment", true));
}

//! The advice a diagnostic gives is code the compiler accepts. Three tables hold the spellings the compiler
//! answers with a replacement: `retired_methods` (`text.upper()` becomes `strings.upper(value)`),
//! `removed_names` (`&&` becomes `and`) and the parser's `declaration_hints` (`del xs[0]` becomes
//! `lists.pop_at(mut xs, index)`). Each message quotes its replacement in backquotes after its first `; `.
//! This test builds a program around every one and requires it to check with no error; a table entry that
//! advises a spelling the compiler refuses fails here, naming the entry, the fragment and the diagnostic.
//!
//! A `removed_names` or `declaration_hints` entry carries its own example program beside its text, and every
//! backquoted fragment of its advice must occur in that program (a hint's example may hold several programs
//! separated by a line of `---`). A `retired_methods` entry names only its replacement's shape, so its program
//! is made from the table: each operand the sketch names becomes a local of the type the entry's family
//! needs, and the replacement call is the statement the message quotes. The calls of one module are checked
//! together in one program of one function each, because every check parses the standard modules again.
const std = @import("std");
const t = std.testing;
const print = std.debug.print;
const fixture = @import("stdlib_fixture.zig");
const parser = @import("parser.zig");
const removed_names = @import("removed_names.zig");
const retired_methods = @import("retired_methods.zig");

/// The text after the first `; ` of a message, where its advice begins; empty when it has none.
fn adviceClause(message: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, message, "; ") orelse return "";
    return message[at + 2 ..];
}

/// Every backquoted fragment of `text`, in order.
fn fragmentsOf(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    var rest = text;
    while (std.mem.indexOfScalar(u8, rest, '`')) |open| {
        const close = std.mem.indexOfScalarPos(u8, rest, open + 1, '`') orelse break;
        try found.append(arena, rest[open + 1 .. close]);
        rest = rest[close + 1 ..];
    }
    return found.items;
}

/// What the compiler said about a program that did not check: the first error's code and message, or why it
/// could not be loaded.
fn refusalOf(arena: std.mem.Allocator, program: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const report = if (fixture.check(arena, program)) |checked| checked else |failure| {
        const unloaded = try std.fmt.allocPrint(arena, "not loaded: {s}", .{@errorName(failure)});
        return unloaded;
    };
    if (report.passed) return null;
    const first = report.firstError() orelse return "refused with no error";
    const refusal = try std.fmt.allocPrint(arena, "{s}: {s}", .{ first.code, first.message });
    return refusal;
}

/// One problem found in a table entry, as the failing test prints it.
fn problem(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8), comptime format: []const u8, args: anytype) std.mem.Allocator.Error!void {
    try problems.append(arena, try std.fmt.allocPrint(arena, format, args));
}

/// Judge one entry's advice against its example programs: each program checks, and each backquoted fragment of
/// `clause` occurs in one of them. An entry with no advice has no example either.
fn judge(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8), name: []const u8, clause: []const u8, example: []const u8) std.mem.Allocator.Error!void {
    const fragments = try fragmentsOf(arena, clause);
    if (clause.len == 0 and example.len != 0) return problem(arena, problems, "{s}: an example but no advice clause", .{name});
    if (clause.len == 0) return;
    if (example.len == 0) return problem(arena, problems, "{s}: advice `{s}` has no example program", .{ name, clause });
    var programs = std.mem.splitSequence(u8, example, "---\n");
    while (programs.next()) |program| {
        if (try refusalOf(arena, program)) |refused| try problem(arena, problems, "{s}: the example program is refused ({s})", .{ name, refused });
    }
    for (fragments) |fragment| {
        if (std.mem.indexOf(u8, example, fragment) == null) try problem(arena, problems, "{s}: the advice quotes `{s}`, which no example program contains", .{ name, fragment });
    }
}

/// Every problem in the parser's hint table.
fn hintProblems(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
    for (parser.declaration_hints) |hint| try judge(arena, problems, hint.idiom, hint.accepted, hint.example);
}

/// Every problem in the removed-name table.
fn removedProblems(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
    for (removed_names.entries) |entry| try judge(arena, problems, entry.removed, adviceClause(entry.message), entry.example);
}

/// The type and starting value of the local an operand of a replacement call stands for.
const Local = struct { ty: []const u8, init: []const u8 };

/// The local that stands for operand `name` of `retirement`'s replacement, or null for the key function a sort
/// names, which is a function of the program. Elements are `int` so that no `own` marker is needed, and a set
/// holds `int` for the same reason.
fn localFor(retirement: retired_methods.Retirement, name: []const u8) ?Local {
    const same = std.mem.eql;
    if (same(u8, name, "key_fn")) return null;
    if (same(u8, name, "flag")) return .{ .ty = "bool", .init = "True" };
    if (same(u8, name, "start") or same(u8, name, "end") or same(u8, name, "index") or same(u8, name, "extra")) return .{ .ty = "int", .init = "0" };
    return switch (retirement.shape) {
        .buffer => bufferLocal(retirement, name),
        .set => setLocal(name),
        .collection => switch (retirement.family) {
            .string => if (same(u8, name, "value")) Local{ .ty = "str", .init = "\"a b\"" } else Local{ .ty = "str", .init = "\"a\"" },
            .bytes => bytesLocal(name),
            .list => listLocal(name),
            .dictionary => dictionaryLocal(name),
        },
    };
}

/// The locals of the `bytes` family: the value and its pieces are `bytes`, the parts of a join a list of them.
fn bytesLocal(name: []const u8) Local {
    if (std.mem.eql(u8, name, "parts")) return .{ .ty = "bytes[]", .init = "[b\"a\"]" };
    return .{ .ty = "bytes", .init = if (std.mem.eql(u8, name, "value")) "b\"ab\"" else "b\"a\"" };
}

/// The locals of the list family: the value and its other are `int` lists.
fn listLocal(name: []const u8) Local {
    if (std.mem.eql(u8, name, "value")) return .{ .ty = "int[]", .init = "[1, 2]" };
    if (std.mem.eql(u8, name, "other")) return .{ .ty = "int[]", .init = "[3]" };
    return .{ .ty = "int", .init = "0" };
}

/// The locals of the dictionary family: text keys and `int` values.
fn dictionaryLocal(name: []const u8) Local {
    const same = std.mem.eql;
    if (same(u8, name, "mapping")) return .{ .ty = "dict[str, int]", .init = "{\"a\": 1}" };
    if (same(u8, name, "other")) return .{ .ty = "dict[str, int]", .init = "{\"b\": 2}" };
    if (same(u8, name, "key")) return .{ .ty = "str", .init = "\"a\"" };
    return .{ .ty = "int", .init = "0" };
}

/// The locals of the `set[T]` operations: sets of `int`.
fn setLocal(name: []const u8) Local {
    if (std.mem.eql(u8, name, "value")) return .{ .ty = "int", .init = "1" };
    return .{ .ty = "set[int]", .init = "set()" };
}

/// The locals of the mutable octet buffer's writes: the buffer, and the pieces its appends take.
fn bufferLocal(retirement: retired_methods.Retirement, name: []const u8) Local {
    const same = std.mem.eql;
    if (same(u8, name, "data")) return .{ .ty = "byte_buffer", .init = "buffers.empty()" };
    if (same(u8, name, "piece")) return .{ .ty = "bytes", .init = "b\"a\"" };
    if (same(u8, name, "text")) return .{ .ty = "str", .init = "\"a\"" };
    if (same(u8, retirement.method, "append_float")) return .{ .ty = "float", .init = "1.5" };
    return .{ .ty = "int", .init = "1" };
}

/// One function of a retirement's program: its operands declared as locals, then the replacement call the
/// message quotes. A replacement that answers an option is tested for absence, as its message says.
fn probeFunction(arena: std.mem.Allocator, out: *std.ArrayList(u8), retirement: retired_methods.Retirement, index: usize) std.mem.Allocator.Error!void {
    const advice = adviceClause(try retired_methods.message(arena, retirement));
    const call = (try fragmentsOf(arena, advice))[0];
    try out.print(arena, "func probe_{d}():\n", .{index});
    const open = std.mem.indexOfScalar(u8, call, '(').?;
    var operands = std.mem.splitSequence(u8, call[open + 1 .. call.len - 1], ", ");
    while (operands.next()) |operand| try declareOperand(arena, out, retirement, operand);
    if (retirement.home.absence == .option)
        try out.print(arena, "    const found: int? = {s}\n    if found is None:\n        return\n", .{call})
    else if (answersView(retirement))
        try out.print(arena, "    for entry in {s}:\n        _ = entry\n", .{call})
    else
        try out.print(arena, "    _ = {s}\n", .{call});
}

/// Whether the replacement answers a dictionary view, which cannot be stored or discarded, only walked.
fn answersView(retirement: retired_methods.Retirement) bool {
    const module = retirement.home.module orelse return false;
    if (!std.mem.eql(u8, module, "dicts")) return false;
    const function = retirement.home.function;
    return std.mem.eql(u8, function, "keys") or std.mem.eql(u8, function, "values") or std.mem.eql(u8, function, "items");
}

/// The declaration of one operand of the sketch: `mut name` is a writable local, `keyword=name` declares `name`.
fn declareOperand(arena: std.mem.Allocator, out: *std.ArrayList(u8), retirement: retired_methods.Retirement, operand: []const u8) std.mem.Allocator.Error!void {
    const writable = std.mem.startsWith(u8, operand, "mut ");
    const named = if (writable) operand[4..] else operand;
    const name = if (std.mem.indexOfScalar(u8, named, '=')) |at| named[at + 1 ..] else named;
    const local = localFor(retirement, name) orelse return;
    try out.print(arena, "    {s} {s}: {s} = {s}\n", .{ if (writable) "mut" else "const", name, local.ty, local.init });
}

/// The program that checks every replacement of the retirements whose home is `module` (null: the prelude).
fn retirementProgram(arena: std.mem.Allocator, module: ?[]const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    if (module) |name| try out.print(arena, "import {s}\n\n", .{name});
    try out.appendSlice(arena, "func key_fn(item: int) -> int:\n    return item\n\n");
    for (retired_methods.retirements, 0..) |retirement, index| {
        if (!sameModule(retirement.home.module, module)) continue;
        try probeFunction(arena, &out, retirement, index);
        try out.appendSlice(arena, "\n");
    }
    try out.appendSlice(arena, "func main() -> int:\n    return 0\n");
    return out.items;
}

/// Whether two optional module names are the same one.
fn sameModule(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

/// Every module that owns a retirement's home, once, with null for the prelude.
fn homeModules(arena: std.mem.Allocator) std.mem.Allocator.Error![]const ?[]const u8 {
    var modules: std.ArrayList(?[]const u8) = .empty;
    for (retired_methods.retirements) |retirement| {
        var known = false;
        for (modules.items) |module| known = known or sameModule(module, retirement.home.module);
        if (!known) try modules.append(arena, retirement.home.module);
    }
    return modules.items;
}

/// A line of context for a refusal of a retirement program: the replacement calls it holds that the message
/// quotes, found one by one when the whole program is refused.
fn culprits(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8), module: ?[]const u8) std.mem.Allocator.Error!void {
    for (retired_methods.retirements, 0..) |retirement, index| {
        if (!sameModule(retirement.home.module, module)) continue;
        var one: std.ArrayList(u8) = .empty;
        if (module) |name| try one.print(arena, "import {s}\n\n", .{name});
        try one.appendSlice(arena, "func key_fn(item: int) -> int:\n    return item\n\n");
        try probeFunction(arena, &one, retirement, index);
        try one.appendSlice(arena, "\nfunc main() -> int:\n    return 0\n");
        const refused = (try refusalOf(arena, one.items)) orelse continue;
        const advice = adviceClause(try retired_methods.message(arena, retirement));
        try problem(arena, problems, "{s}() on a {s}: advice `{s}` is refused ({s})", .{ retirement.method, @tagName(retirement.family), advice, refused });
    }
}

/// The fragments of every retirement's advice occur in its module's program (the calls, `int?` and `is None`),
/// and the message of a replacement that answers nothing quotes the same call.
fn retirementFragments(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8), module: ?[]const u8, program: []const u8) std.mem.Allocator.Error!void {
    for (retired_methods.retirements) |retirement| {
        if (!sameModule(retirement.home.module, module)) continue;
        const advice = adviceClause(try retired_methods.message(arena, retirement));
        for (try fragmentsOf(arena, advice)) |fragment| {
            if (std.mem.indexOf(u8, program, fragment) == null) try problem(arena, problems, "{s}(): the advice quotes `{s}`, which its program does not contain", .{ retirement.method, fragment });
        }
        if (retirement.answer != .nothing) continue;
        const bare = adviceClause(try retired_methods.nothingMessage(arena, retirement));
        for (try fragmentsOf(arena, bare)) |fragment| {
            if (std.mem.indexOf(u8, program, fragment) == null) try problem(arena, problems, "{s}(): the statement advice quotes `{s}`, which its program does not contain", .{ retirement.method, fragment });
        }
    }
}

/// Every problem in the retirement table: one program per module of the replacements.
fn retirementProblems(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
    for (try homeModules(arena)) |module| {
        const program = try retirementProgram(arena, module);
        try retirementFragments(arena, problems, module, program);
        if (try refusalOf(arena, program) != null) try culprits(arena, problems, module);
    }
}

/// The stream methods' replacements: `print(out, value)` and `write(out, data)`, each in a function of its own.
fn streamProblems(arena: std.mem.Allocator, problems: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
    for (retired_methods.stream_methods) |entry| {
        const advice = adviceClause(try retired_methods.streamMessage(arena, entry, true));
        const call = (try fragmentsOf(arena, advice))[0];
        const data = if (std.mem.eql(u8, entry.function, "write")) "b\"a\"" else "1";
        const program = try std.fmt.allocPrint(arena, "func probe(out: Stream):\n    const value = {s}\n    const data = {s}\n    {s}\n\nfunc main() -> int:\n    return 0\n", .{ data, data, call });
        if (try refusalOf(arena, program)) |refused| try problem(arena, problems, "{s}() on a stream: advice `{s}` is refused ({s})", .{ entry.method, call, refused });
    }
}

/// Print every problem a table check found, so a failing run names each entry that advises a refused spelling.
fn printProblems(problems: []const []const u8) void {
    for (problems) |line| print("advice table: {s}\n", .{line});
}

/// Run `check` against a fresh arena and require that it finds no problem.
fn expectNoProblems(comptime check: fn (std.mem.Allocator, *std.ArrayList([]const u8)) std.mem.Allocator.Error!void) !void {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    var problems: std.ArrayList([]const u8) = .empty;
    try check(arena.allocator(), &problems);
    printProblems(problems.items);
    try t.expectEqual(@as(usize, 0), problems.items.len);
}

test "every replacement the declaration hints advise is code the compiler accepts" {
    try expectNoProblems(hintProblems);
}

test "every replacement the removed-spelling messages advise is code the compiler accepts" {
    try expectNoProblems(removedProblems);
}

test "every replacement the retired-method messages advise is code the compiler accepts" {
    try expectNoProblems(retirementProblems);
}

test "every replacement the stream-method messages advise is code the compiler accepts" {
    try expectNoProblems(streamProblems);
}

test "the retirement table covers every module and a retirement with an option answer" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const modules = try homeModules(arena.allocator());
    try t.expect(modules.len >= 6);
    const program = try retirementProgram(arena.allocator(), "strings");
    try t.expect(std.mem.indexOf(u8, program, "const found: int? = strings.find(value, needle)") != null);
    try t.expect(std.mem.indexOf(u8, program, "if found is None:") != null);
}

test "a refused spelling in an advice clause is found, with its entry and fragment" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    var problems: std.ArrayList([]const u8) = .empty;
    try judge(arena.allocator(), &problems, "del", "remove with `_ = xs.pop(index)`", "func main() -> int:\n    mut xs = [1, 2]\n    _ = xs.pop(0)\n    return len(xs)\n");
    try t.expect(problems.items.len >= 1);
    try t.expect(std.mem.indexOf(u8, problems.items[0], "E_METHOD_REMOVED") != null);
    try judge(arena.allocator(), &problems, "chained", "write `const x = 21`", "func main() -> int:\n    return 0\n");
    try t.expect(std.mem.indexOf(u8, problems.items[problems.items.len - 1], "`const x = 21`") != null);
}

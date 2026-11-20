//! Executable source contracts for checked ownership, borrowing, and explicit copies.
const std = @import("std");
const report = std.debug.print;
const language = @import("selka");
const unique = @import("single_owner.zig");
const files = @import("single_owner_files.zig");
const receiver_repair = @import("receiver_repair.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    return support.checkedProgram(a, source);
}

fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.check(a, try checked(a, source), &failure));
    if (!std.mem.eql(u8, code, failure.code)) report("unexpected refusal: {s} at {d}\n", .{ failure.message, failure.span.start });
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(failure.span.end >= failure.span.start);
    try std.testing.expect(failure.message.len != 0);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
}

fn missingContract(backing: std.mem.Allocator, source: []const u8, clause: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_BORROW_UNDECLARED", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R4, failure.rule.?);
    try std.testing.expect(failure.repair == .explicit_fix);
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 1), edits.len);
    const edit = edits[0];
    try std.testing.expectEqualStrings(clause, edit.text);
    try std.testing.expectEqual(edit.span.start, edit.span.end);
    const repaired = try std.mem.concat(a, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    const after = try support.checkSource(a, repaired);
    try std.testing.expect(after.passed);
    failure = .{};
    try unique.checkWithSource(a, after.program.?, after.src.?, &failure);
}

fn refusesRelated(backing: std.mem.Allocator, source: []const u8, code: []const u8, message_fragment: []const u8, related_fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.check(a, try checked(a, source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
    try std.testing.expect(std.mem.indexOf(u8, failure.message, message_fragment) != null);
    try std.testing.expect(failure.notes.related != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.notes.related.?.message, related_fragment) != null);
}

fn refusesContaining(backing: std.mem.Allocator, source: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.check(a, try checked(a, source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
}

/// Like `refusesContaining`, with the source, so a message can quote the arguments as the program spells them.
fn refusesQuoting(backing: std.mem.Allocator, source: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
}

const ReceiverDiagnostic = struct {
    code: []const u8 = "E_SINGLE_OWNER_OVERLAP",
    rule: language.ownership_rules.Rule = .R2,
    receiver: bool = false,
    split: bool = false,
    copy: bool = false,
};

fn receiverDiagnostic(backing: std.mem.Allocator, text: []const u8, expected: ReceiverDiagnostic) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try support.checkSource(a, text);
    try std.testing.expect(result.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, result.program.?, result.src.?, &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
    try std.testing.expectEqual(expected.receiver, failure.repair == .receiver);
    var rendered: std.ArrayList(u8) = .empty;
    try unique.render(a, result.src.?, failure, .json, &rendered);
    try std.testing.expectEqual(expected.split, std.mem.indexOf(u8, rendered.items, "const mutation_result_") != null);
    try std.testing.expectEqual(expected.copy, std.mem.indexOf(u8, rendered.items, "\"text\":\"copy(\"") != null);
    if (expected.split) {
        const fix = (try receiver_repair.prove(a, result.src.?, failure.repair.receiver)).?;
        try std.testing.expectEqual(@as(usize, 2), fix.count());
        const insertion = fix.edit;
        const replacement = fix.more[0];
        try std.testing.expectEqual(insertion.span.start, insertion.span.end);
        try std.testing.expect(insertion.span.end <= replacement.span.start);
        const repaired = try std.mem.concat(a, u8, &.{
            text[0..insertion.span.start], insertion.text, text[insertion.span.end..replacement.span.start], replacement.text, text[replacement.span.end..],
        });
        const after = try support.checkSource(a, repaired);
        try std.testing.expect(after.passed);
        failure = .{};
        try unique.checkWithSource(a, after.program.?, after.src.?, &failure);
        try std.testing.expectEqualStrings("", failure.message);
    }
}

const receiver_helpers =
    \\func selected(mut items: int[]) -> int:
    \\    append(mut items, 3)
    \\    return 0
    \\
    \\
;

test "O2 ownership checkLoans receiver repair renders only after a scalar mutation conflicts with its live receiver" {
    try receiverDiagnostic(std.testing.allocator, receiver_helpers ++
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    items[selected(mut items)] = 9
        \\    return items[0] + len(items)
    , .{ .receiver = true, .split = true });
    try receiverDiagnostic(std.testing.allocator,
        // migrate-embedded: skip original receiver-overlap refusal and evaluation-order repair witness
        \\record Point:
        \\    x: int
        \\func selected(mut items: Point[]) -> int:
        \\    append(mut items, Point(x=3))
        \\    return 0
        \\func main() -> int:
        \\    mut items = [Point(x=1)]
        \\    items[selected(mut items)].x = 9
        \\    return items[0].x
    , .{ .receiver = true, .split = true });
    try receiverDiagnostic(std.testing.allocator, receiver_helpers ++
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    items[selected(mut items)] = items[0]
        \\    return items[0]
    , .{ .receiver = true });
}

test "O2 ownership checkLoans receiver repair preserves moves unrelated loans and live view copies" {
    try receiverDiagnostic(std.testing.allocator,
        // migrate-embedded: skip original receiver-overlap refusal and evaluation-order repair witness
        \\func my_take(own items: int[]) -> int:
        \\    return 0
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    items[my_take(own items)] = 9
        \\    return 0
    , .{ .copy = true });
    try receiverDiagnostic(std.testing.allocator,
        \\func selected(mut items: int[]) -> str:
        \\    append(mut items, 3)
        \\    return "zero"
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    items[len(selected(mut items))] = 9
        \\    return 0
    , .{});
    try receiverDiagnostic(std.testing.allocator,
        \\func together(items: int[], mut other: int[]) -> int:
        \\    return len(items) + len(other)
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    return together(items, mut items)
    , .{ .rule = .M5 });
    try receiverDiagnostic(std.testing.allocator,
        \\func selected(mut items: int[][]) -> int:
        \\    append(mut items, [3])
        \\    return 0
        \\func main() -> int:
        \\    mut items = [[1], [2]]
        \\    const borrowed = items[0]
        \\    _ = selected(mut items)
        \\    return len(borrowed)
    , .{});
    try receiverDiagnostic(std.testing.allocator, receiver_helpers ++
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    const piece = items[0:1]
        \\    items[selected(mut items)] = 9
        \\    return piece[0]
    , .{});
    try receiverDiagnostic(std.testing.allocator,
        \\func selected(mut items: str) -> int:
        \\    items = items + "c"
        \\    return 0
        \\func main() -> int:
        \\    mut items = "ab"
        \\    const piece = items[0:1]
        \\    return len(items[selected(mut items):]) + len(piece)
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V3, .copy = true });
}

// spec: NEW-CORE-SINGLE-OWNER-1
test "single owner rejects use after assignment and container insertion moves" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1, 2]
        \\    const ys = own xs
        \\    return len(xs) + len(ys)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1, 2]
        \\    const rows = [own xs]
        \\    return len(xs) + len(rows)
    , "E_SINGLE_OWNER_MOVED");
}

test "O2 ownership Core refuses projected literal match copies" {
    try refuses(std.testing.allocator,
        \\record Entry:
        \\    text: str
        \\func main() -> int:
        \\    const entry = Entry(text="one")
        \\    match entry.text:
        \\        case "one":
        \\            return 1
        \\        case _:
        \\            return 0
    , "E_LITERAL_ARM");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values = [b"one"]
        \\    match values[0]:
        \\        case b"one":
        \\            return 1
        \\        case _:
        \\            return 0
    , "E_LITERAL_ARM");
}

test "O2 ownership Core keeps open files within their with scope" {
    try refuses(std.testing.allocator,
        \\func consume(own file: File) -> int:
        \\    return 0
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("note", "rb") as file:
        \\        _ = consume(own file)
        \\    return 0
    , "E_WITH_RESOURCE");
    try refuses(std.testing.allocator,
        \\func keep(fs: Filesystem) -> File:
        \\    with fs.open("note", "rb") as file:
        \\        return file
        \\func main() -> int:
        \\    return 0
    , "E_WITH_RESOURCE");
}

test "an open file's refusal says what the with block refuses and what to write instead" {
    const lend = "call its methods there, or lend it to a helper declared `mut f: File` and called as `put(mut f, data)`";
    try refusesContaining(std.testing.allocator,
        \\func consume(own file: File) -> int:
        \\    return 0
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("note", "rb") as file:
        \\        _ = consume(own file)
        \\    return 0
    , "E_WITH_RESOURCE", "an open file belongs to its `with` block, so it cannot be returned, stored or given away with `own`; " ++ lend);
    try refusesContaining(std.testing.allocator,
        \\func keep(fs: Filesystem) -> File:
        \\    with fs.open("note", "rb") as file:
        \\        return file
        \\func main() -> int:
        \\    return 0
    , "E_WITH_RESOURCE", "an open file belongs to its `with` block, so it cannot be returned, stored or given away with `own`; " ++ lend);
    // A list of files is a type the front end refuses where it is written, in the words the ownership check gives a local that holds one.
    try refusedWhereWritten(std.testing.allocator,
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("note", "rb") as file:
        \\        const files = [file]
        \\        return len(files)
    , "an open file cannot be held inside a list, record, variant or callback type: it belongs to its `with` block; call its methods there, or lend it to a helper declared `mut f: File` and called as `put(mut f, data)`");
}

test "O2 ownership Core protects field assignment receivers during staged index evaluation" {
    try refusesRule(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\func save(mut points: Point[]) -> int:
        \\    append(mut points, Point(x=1))
        \\    return 0
        \\func main() -> int:
        \\    mut points = [Point(x=0)]
        \\    points[save(mut points)].x = 13
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
    try refusesRule(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\    tags: int[]
        \\func save(mut points: Point[]) -> int:
        \\    points = [Point(x=8, tags=[2])]
        \\    return 0
        \\func main() -> int:
        \\    mut points = [Point(x=0, tags=[1])]
        \\    points[save(mut points)].x = 13
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
    try refusesRule(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[]
        \\    right: int[]
        \\func replace(mut points: Point[]) -> int:
        \\    points = [Point(x=8)]
        \\    return 0
        \\func main() -> int:
        \\    mut points = Fields(left=[Point(x=0)], right=[0])
        \\    points.left[replace(mut points.left)].x = 13
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
    try refusesRule(std.testing.allocator,
        \\import lists
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[]
        \\    right: int[]
        \\func main() -> int:
        \\    mut points = Fields(left=[Point(x=0)], right=[0])
        \\    points.left[lists.pop(mut points.left).x].x = 13
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
}

fn accepts(a: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var failure: unique.Failure = .{};
    try unique.check(arena.allocator(), try checked(arena.allocator(), text), &failure);
    try std.testing.expectEqualStrings("", failure.message);
}

/// The checker accepts `text` and Core builds it. Core refused each of these until FR73 (Z3, "write to a receiver's place
/// while its arguments are evaluated"); it now reads the receiver again from its root after an index that wrote a sibling
/// field, as the plain form with the index bound first does. `tests/lang/nested_element_fields.selka` runs them.
fn buildsReceiver(backing: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, text);
    var failure: unique.Failure = .{};
    try unique.check(a, program, &failure);
    try std.testing.expectEqualStrings("", failure.message);
    var refusal: build.Refusal = .{};
    _ = try build.buildModule(a, program, &refusal);
    try std.testing.expectEqual(@as(?language.ownership_rules.Rule, null), refusal.rule);
}

test "O2 ownership Core keeps sibling receiver paths disjoint during staged index evaluation" {
    try buildsReceiver(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[]
        \\    right: int[]
        \\func save(mut right: int[]) -> int:
        \\    append(mut right, 1)
        \\    return 0
        \\func main() -> int:
        \\    mut points = Fields(left=[Point(x=0)], right=[0])
        \\    points.left[save(mut points.right)].x = 13
        \\    return points.left[0].x
    );
    try buildsReceiver(std.testing.allocator,
        \\import lists
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[]
        \\    right: int[]
        \\func main() -> int:
        \\    mut points = Fields(left=[Point(x=0)], right=[0])
        \\    points.left[lists.pop(mut points.right)].x = 13
        \\    return points.left[0].x
    );
    try buildsReceiver(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[][]
        \\    right: int[]
        \\func save(mut right: int[]) -> int:
        \\    append(mut right, 1)
        \\    return 0
        \\func main() -> int:
        \\    mut points = Fields(left=[[Point(x=0)]], right=[0])
        \\    points.left[0][save(mut points.right)].x = 13
        \\    return points.left[0][0].x
    );
    try buildsReceiver(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[][]
        \\    right: int[]
        \\func save(mut right: int[]) -> int:
        \\    append(mut right, 1)
        \\    return 0
        \\func inspect(mut points: Fields, index: int) -> int:
        \\    points.left[index][save(mut points.right)].x = 13
        \\    return points.left[index][0].x
        \\func main() -> int:
        \\    mut points = Fields(left=[[Point(x=0)]], right=[0])
        \\    return inspect(mut points, 0)
    );
    try buildsReceiver(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[]
        \\    right: int[][]
        \\func save(mut right: int[]) -> int:
        \\    append(mut right, 1)
        \\    return 0
        \\func inspect(mut points: Fields, index: int) -> int:
        \\    points.left[save(mut points.right[index])].x = 13
        \\    return points.left[0].x
        \\func main() -> int:
        \\    mut points = Fields(left=[Point(x=0)], right=[[0]])
        \\    return inspect(mut points, 0)
    );
}

test "O2 ownership staged receiver proof keeps shared list indices and ancestor writes overlapping" {
    try refusesRule(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[][]
        \\    right: int[]
        \\func replace(mut points: Fields) -> int:
        \\    points.left = [[Point(x=8)]]
        \\    return 0
        \\func main() -> int:
        \\    mut points = Fields(left=[[Point(x=0)]], right=[0])
        \\    points.left[0][replace(mut points)].x = 13
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
    try refusesRule(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[]
        \\    right: int[]
        \\func save(mut right: int[]) -> int:
        \\    append(mut right, 1)
        \\    return 0
        \\func main() -> int:
        \\    mut points = [Fields(left=[Point(x=0)], right=[0]), Fields(left=[Point(x=0)], right=[0])]
        \\    points[0].left[save(mut points[1].right)].x = 13
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
    try refusesRule(std.testing.allocator,
        \\record Point:
        \\    x: int
        \\record Fields:
        \\    left: Point[]
        \\    right: int[]
        \\func consume(own points: Fields) -> int:
        \\    return 0
        \\func main() -> int:
        \\    mut points = Fields(left=[Point(x=0)], right=[0])
        \\    points.left[consume(own points)].x = 13
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
}

fn refusesRule(backing: std.mem.Allocator, text: []const u8, expected: language.ownership_rules.Refusal) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.check(arena.allocator(), try checked(arena.allocator(), text), &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
}

/// A type that stores an open file is refused by the front end where the type is written (`record_layouts.zig`), before the ownership
/// check has a local to walk, with this code, rule P4 and the words of `fragment`.
fn refusedWhereWritten(backing: std.mem.Allocator, source: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), source);
    try std.testing.expect(!unit.passed);
    try std.testing.expectEqualStrings("E_WITH_RESOURCE", unit.diagnostics[0].code);
    try std.testing.expectEqual(language.ownership_rules.Rule.P4, unit.diagnostics[0].provenance.rule.?);
    if (std.mem.indexOf(u8, unit.diagnostics[0].message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, unit.diagnostics[0].message });
    try std.testing.expect(std.mem.indexOf(u8, unit.diagnostics[0].message, fragment) != null);
}

test "O2 nested files stay in named scopes across generic and callback types: the front end refuses the type where it is written" {
    try refusedWhereWritten(std.testing.allocator,
        \\record Envelope[T]:
        \\    value: T
        \\func inspect(own value: Envelope[File]) -> int:
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "an open file cannot be held inside a list, record, variant or callback type");
    try refusedWhereWritten(std.testing.allocator,
        \\func inspect(callback: func(own File) -> int) -> int:
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "an open file cannot be held inside a list, record, variant or callback type");
    try accepts(std.testing.allocator,
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\func forward(own file: File) -> Open:
        \\    return Open.ok(own file)
        \\func main() -> int:
        \\    return 0
    );
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner requires a return contract and rejects retaining borrowed parameters" {
    try missingContract(std.testing.allocator,
        // migrate-embedded: skip original missing-from return-contract repair witness
        \\func keep(xs: int[]) -> int[]:
        \\    return xs
        \\func main() -> int:
        \\    return len(keep([1]))
    , " from xs");
    try missingContract(std.testing.allocator,
        \\func head(source: str) -> str from source:
        \\    return source[0:1]
        \\func lead(data: str) -> str:
        \\    return head(data)
        \\func main() -> int:
        \\    return len(lead("abc"))
    , " from data");
    try refuses(std.testing.allocator,
        \\func change(xs: int[]) -> int:
        \\    mut ys = xs
        \\    append(mut ys, 2)
        \\    return len(ys)
        \\func main() -> int:
        \\    return change([1])
    , "E_SINGLE_OWNER_BORROW");
    // R3b: a field of a record parameter returned is an accepted borrow (see borrowed_return_test.zig).
}

const fallible_borrow =
    \\func plain(data: bytes, position: int) -> bytes from data fails str:
    \\    if position > len(data):
    \\        fail "short"
    \\    return data[position:]
    \\
    \\
;

test "F3 try binds the success of a borrowed call as a loan on the call's owner" {
    try refuses(std.testing.allocator, fallible_borrow ++
        \\func use(own data: bytes) -> int fails str:
        \\    mut owner = own data
        \\    const part = try plain(owner, 1)
        \\    owner = b"replaced"
        \\    return len(part)
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try accepts(std.testing.allocator, fallible_borrow ++
        \\func use(own data: bytes) -> int fails str:
        \\    mut owner = own data
        \\    const part = try plain(owner, 1)
        \\    const size = len(part)
        \\    owner = b"replaced"
        \\    return size + len(owner)
        \\func main() -> int:
        \\    return 0
    );
}

test "F3 try returns a borrowed success only through the declared sources" {
    try refusesRule(std.testing.allocator, fallible_borrow ++
        \\func use(data: bytes) -> bytes fails str:
        \\    const part = try plain(data, 1)
        \\    return part
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_BORROW_UNDECLARED", .rule = .R4 });
    try accepts(std.testing.allocator, fallible_borrow ++
        \\func forward(data: bytes) -> bytes from data fails str:
        \\    return try plain(data, 1)
        \\func main() -> int:
        \\    return 0
    );
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner rejects read and mut overlap in direct and nested calls" {
    try refuses(std.testing.allocator,
        \\func both(xs: int[], mut ys: int[]) -> int:
        \\    append(mut ys, 3)
        \\    return len(xs)
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return both(xs, mut xs)
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func change(mut xs: int[]) -> int:
        \\    append(mut xs, 3)
        \\    return 0
        \\func read(xs: int[], n: int) -> int:
        \\    return len(xs) + n
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return read(xs, change(mut xs))
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner joins branches and rejects moves across loop backedges" {
    try refuses(std.testing.allocator,
        \\func probe(flag: bool) -> int:
        \\    const xs = [1]
        \\    if flag:
        \\        const ys = own xs
        \\        assert len(ys) == 1
        \\    return len(xs)
        \\func main() -> int:
        \\    return probe(True)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1]
        \\    for i in range(3):
        \\        const ys = own xs
        \\        assert len(ys) == 1
        \\    return 0
    , "E_SINGLE_OWNER_LOOP");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner iteration borrows prevent mutating the iterated root" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    for x in xs:
        \\        append(mut xs, x)
        \\    return len(xs)
    , "E_SINGLE_OWNER_OVERLAP");
}

const sample =
    \\record Batch:
    \\    items: int[]
    \\    factor: int
    \\func fill(mut xs: int[], n: int):
    \\    for i in range(n):
    \\        append(mut xs, i + 1)
    \\func my_sum(xs: int[]) -> int:
    \\    mut total = 0
    \\    for x in xs:
    \\        total += x
    \\    return total
    \\func recursive(xs: int[], i: int) -> int:
    \\    if i == len(xs):
    \\        return 0
    \\    return xs[i] + recursive(xs, i + 1)
    \\func copied(xs: int[]) -> int[]:
    \\    return copy(xs)
    \\func make(n: int) -> Batch:
    \\    mut xs: int[] = []
    \\    fill(mut xs, n)
    \\    return Batch(items=own xs, factor=n)
    \\func score(b: Batch) -> int:
    \\    return my_sum(b.items) * b.factor
    \\func main(out: Stream) -> int:
    \\    const batch = make(4)
    \\    mut xs = copied(batch.items)
    \\    fill(mut xs, 2)
    \\    const ys = xs
    \\    print(out, score(batch), my_sum(ys), recursive(ys, 0))
    \\    return 0
;

fn executes(backing: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: unique.Failure = .{};
    unique.check(a, program, &failure) catch |err| {
        report("single owner check: {s} at {d}\n", .{ failure.message, failure.span.start });
        return err;
    };
    inline for (.{ false, true }) |release| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
        const result = if (release) try passes.run(a, &module, .verify) else try passes.debug(a, &module);

        try support.verified(a, &module, result.plans);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = release, .verify = release, .analysis = support.analysis(&result) });
        if (run.status != 0) report("single owner execution release={any}:\n{s}{s}\n", .{ release, run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
    }
}

// spec: NEW-CORE-SINGLE-OWNER-2
test "single owner explicit copies fresh returns mut helpers recursion and records execute" {
    try executes(std.testing.allocator, sample, "40 13 13\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested explicit copies preserve independent child lists" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    const row = [1, 2]
        \\    const rows = [own row]
        \\    mut copied = copy(rows)
        \\    append(mut copied[0], 3)
        \\    print(out, len(rows[0]), len(copied[0]))
        \\    return 0
    , "2 3\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner accepts reinitialization after a move and terminating branches" {
    try executes(std.testing.allocator,
        \\func probe(flag: bool) -> int:
        \\    mut xs = [1]
        \\    if flag:
        \\        const ys = own xs
        \\        return len(ys)
        \\    const ys = own xs
        \\    xs = [3, 4]
        \\    return len(xs) + len(ys)
        \\func main(out: Stream) -> int:
        \\    print(out, probe(False), probe(True))
        \\    return 0
    , "3 1\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner rejects moves in repeated conditions and overlapping builtin arguments" {
    try refuses(std.testing.allocator,
        \\record Box:
        \\    values: int[]
        \\func more(box: Box) -> bool:
        \\    return len(box.values) > 0
        \\func main() -> int:
        \\    const xs = [1]
        \\    while more(Box(values=own xs)):
        \\        pass
        \\    return 0
    , "E_SINGLE_OWNER_LOOP");
    try refuses(std.testing.allocator,
        \\func change(mut xs: int[]) -> int:
        \\    append(mut xs, 4)
        \\    return 0
        \\func main(out: Stream) -> int:
        \\    mut xs = [1]
        \\    print(out, xs, change(mut xs))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func change(mut xs: int[]) -> int:
        \\    append(mut xs, 4)
        \\    return 0
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return xs[change(mut xs)]
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner record mutation and nested record copies execute" {
    try executes(std.testing.allocator,
        \\record Row:
        \\    values: int[]
        \\    factor: int
        \\func change(mut row: Row):
        \\    append(mut row.values, 4)
        \\    row.factor += 1
        \\func main(out: Stream) -> int:
        \\    mut row = Row(values=[1, 2], factor=3)
        \\    change(mut row)
        \\    const rows = [own row]
        \\    mut copied = copy(rows)
        \\    append(mut copied[0].values, 7)
        \\    print(out, len(rows[0].values), len(copied[0].values), rows[0].factor)
        \\    return 0
    , "3 4 4\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner pop transfers child storage and branch cleanup remains exact" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\func probe(flag: bool) -> int:
        \\    mut rows = [[1, 2], [3]]
        \\    mut last = lists.pop(mut rows)
        \\    append(mut last, 4)
        \\    if flag:
        \\        return len(rows[0]) + len(last)
        \\    return len(last)
        \\func main(out: Stream) -> int:
        \\    print(out, probe(True), probe(False))
        \\    return 0
    , "4 2\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-1
test "single owner validation errors survive rendering and allocation failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func main() -> int:
        \\    const xs = [1]
        \\    const ys = own xs
        \\    return len(xs) + len(ys)
    ;
    const program = try checked(a, source);
    const src = try language.source.Source.init(a, "single-owner.selka", source);
    var diagnostics: std.ArrayList(u8) = .empty;
    try std.testing.expect(!try unique.validate(a, std.testing.allocator, program, src, .json, &diagnostics));
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.items, "E_SINGLE_OWNER_MOVED") != null);
    var empty: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&empty);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.OutOfMemory, unique.check(fixed.allocator(), program, &failure));
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested cleanup handles wide records and independent text leaves" {
    try executes(std.testing.allocator,
        \\import lists
        \\import strings
        \\
        \\record Row:
        \\    first: int[]
        \\    second: int[][]
        \\    name: str
        \\    a: int
        \\    b: int
        \\func probe(n: int, early: bool) -> int:
        \\    const name = str(n)
        \\    mut rows = [Row(first=[n], second=[[n + 1], []], name=copy(name), a=1, b=2)]
        \\    const saved = copy(rows)
        \\    rows = [Row(first=[], second=[], name=copy(name), a=3, b=4)]
        \\    if early:
        \\        return saved[0].first[0] + strings.char_count(saved[0].name)
        \\    lists.clear(mut rows)
        \\    return saved[0].second[0][0] + strings.char_count(name)
        \\func main(out: Stream) -> int:
        \\    print(out, probe(123, True), probe(123, False))
        \\    return 0
    , "126 127\n");
}

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested cleanup traverses fixed arrays containing lists" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\func main(out: Stream) -> int:
        \\    const pair = FixedArray[int[], 2]([[1, 2], [3]])
        \\    mut rows = [own pair]
        \\    print(out, rows[0][0][1], rows[0][1][0])
        \\    lists.clear(mut rows)
        \\    return 0
    , "2 3\n");
}

// spec-case: OWNED-LIST-EXCHANGE-1
test "single owner exchange consumes replacements and rejects borrowed or overlapping donors" {
    try refuses(std.testing.allocator,
        \\import lists
        \\
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    const donor = [2]
        \\    _ = lists.exchange(mut rows, 0, own donor)
        \\    return len(donor)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\import lists
        \\
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    _ = lists.exchange(mut rows, 0, rows[1])
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: OWNED-LIST-EXCHANGE-1
test "single owner exchange refuses receiver relocation while evaluating arguments" {
    try rejectsExchangeRelocation(std.testing.allocator,
        \\import lists
        \\
        \\func grow(mut xs: int[]) -> int:
        \\    append(mut xs, 3)
        \\    return -1
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    _ = lists.exchange(mut xs, grow(mut xs), 9)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try rejectsExchangeRelocation(std.testing.allocator,
        \\import lists
        \\
        \\func replacement(mut xs: int[]) -> int:
        \\    append(mut xs, 3)
        \\    return 9
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    _ = lists.exchange(mut xs, 0, replacement(mut xs))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

fn rejectsExchangeRelocation(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    // The fixtures import `lists` for `lists.exchange` (W13-S5), so they are checked as embedded projects.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.check(a, try checked(a, text), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R2, failure.rule.?);
}

// spec: SINGLE-OWNER-DIAG-1
test "single owner: a pattern payload and an indexed row of a parameter are returned as borrows (R3b)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    try unique.check(a, try checked(a,
        \\enum Failure:
        \\    Bad(value: str)
        \\func message(failure: Failure) -> str from failure:
        \\    match failure:
        \\        case Bad(value=detail):
        \\            return detail
        \\func main() -> int:
        \\    return 0
    ), &failure);
    try unique.check(a, try checked(a,
        \\func first(rows: str[][], index: int) -> str[] from rows:
        \\    const row = rows[index]
        \\    return row
        \\func main() -> int:
        \\    return 0
    ), &failure);
}
test "single owner loop refusal names the binding and links its move" {
    try refusesRelated(std.testing.allocator,
        \\func main() -> int:
        \\    const xs = [1]
        \\    for i in range(3):
        \\        const ys = own xs
        \\        assert len(ys) == 1
        \\    return 0
    , "E_SINGLE_OWNER_LOOP", "'xs' is moved inside a loop", "'xs' is moved here");
}

// spec: SINGLE-OWNER-DIAG-3
test "single owner moved refusal links the move that consumed the value" {
    try refusesRelated(std.testing.allocator,
        \\record Box:
        \\    values: str[]
        \\
        \\
        \\func main() -> int:
        \\    const xs: str[] = []
        \\    const box = Box(values=own xs)
        \\    return len(xs) + len(box.values)
    , "E_SINGLE_OWNER_MOVED", "'xs' was moved or is unavailable", "'xs' is moved here");
}

// spec: SINGLE-OWNER-DIAG-4
test "single owner overlap inside a match names the match and its repairs" {
    try refusesRelated(std.testing.allocator,
        \\enum Found:
        \\    none
        \\    found(destination: bytes, end: int)
        \\
        \\
        \\func attempt(src: bytes) -> Found:
        \\    if len(src) == 0:
        \\        return Found.none
        \\    return Found.found(destination=copy(src), end=len(src))
        \\
        \\
        \\func first(src: bytes) -> Found:
        \\    const tried = attempt(src)
        \\    match tried:
        \\        case found(destination=_, end=_):
        \\            return tried
        \\        case none:
        \\            return Found.none
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP", "'tried' is the value of a `match` whose arm is running, and a match on a named value keeps borrowing it; " ++
        "a copy(value) here runs on every call or iteration, so match on the call that produces it (`match f(x):`) " ++
        "so the payload transfers, or test a bool or option before the match and make the call after it returns", "borrowed by this match");
}

/// FR80's program: `match t.keys[at]:` whose `case CASE:` arm runs `ARM`, with `Key` holding `PAYLOAD` in `num` and
/// `Table` holding `keys: Key[]`, `ints: dict[int, int]` and `seen: int[]`.
fn tableKeyArm(comptime scrutinee: []const u8, comptime payload: []const u8, comptime arm: []const u8) []const u8 {
    return "enum Key:\n    num(v: " ++ payload ++ ")\n    other\n\n\nrecord Table:\n    key: Key\n    keys: Key[]\n" ++
        "    ints: dict[int, int]\n    seen: int[]\n\n\nfunc index_at(mut t: Table, at: int):\n    match " ++ scrutinee ++
        ":\n        case num(v=n):\n" ++ arm ++ "        case other:\n            pass\n\n\nfunc main() -> int:\n    return 0\n";
}

// spec-case: SINGLE-OWNER-DIAG-4
test "a match arm whose fielded payload holds numbers writes a field beside the matched place (FR80)" {
    try accepts(std.testing.allocator, tableKeyArm("t.keys[at]", "int", "            t.ints[n] = at\n"));
    try accepts(std.testing.allocator, tableKeyArm("t.key", "int", "            t.ints[n] = at\n"));
    try accepts(std.testing.allocator, tableKeyArm("t.keys[at]", "int", "            append(mut t.seen, n)\n"));
}

// spec-case: SINGLE-OWNER-DIAG-4
test "a match arm whose payload of numbers replaces the matched element or the list that holds it is accepted (FR93)" {
    // FR80 refused these ("not that place or one that holds it"); the payload is copied when bound, as `case Some(sec)` is.
    try accepts(std.testing.allocator, tableKeyArm("t.keys[at]", "int", "            t.keys[at] = Key.other\n            t.ints[n] = at\n"));
    try accepts(std.testing.allocator, tableKeyArm("t.keys[at]", "int", "            append(mut t.keys, Key.other)\n            t.ints[n] = at\n"));
    try accepts(std.testing.allocator, tableKeyArm("t.keys[at]", "bool", "            t.keys[at] = Key.other\n            if n:\n                t.ints[at] = at\n"));
    try accepts(std.testing.allocator, tableKeyArm("t.key", "int", "            t.key = Key.other\n            t.ints[n] = at\n"));
}

// spec-case: SINGLE-OWNER-DIAG-4
test "a match arm whose payload holds text keeps its container held for a write beside it (FR80)" {
    const beside = tableKeyArm("t.keys[at]", "str", "            t.ints[at] = len(n)\n");
    try refusesQuoting(std.testing.allocator, beside, "E_SINGLE_OWNER_OVERLAP", "`match t.keys[at]:` borrows 't' until its running arm's last use of a payload binding, so this change of " ++
        "'t.ints[at]' is refused, because the payload binding reads what it holds there; match a copy " ++
        "(`match copy(t.keys[at]):`, cheap when the payload is numbers) or read what the arm needs into a local before " ++
        "the match and change 't.ints[at]' after it");
    try refusesQuoting(std.testing.allocator, tableKeyArm("t.keys[at]", "str", "            append(mut t.seen, len(n))\n"), "E_SINGLE_OWNER_OVERLAP", "so this change of 't.seen' is refused");
    // A payload of text keeps the matched place held too, which a payload of numbers no longer does (FR93).
    try refusesQuoting(std.testing.allocator, tableKeyArm("t.keys[at]", "str", "            t.keys[at] = Key.other\n            t.ints[at] = len(n)\n"), "E_SINGLE_OWNER_OVERLAP", "so this change of 't.keys[at]' is refused, because the payload binding reads what it holds there");
}

// spec-case: SINGLE-OWNER-DIAG-4
test "a match mut arm whose payload holds numbers keeps its tracked container held for a write beside it (FR80)" {
    try refusesQuoting(std.testing.allocator, tableKeyArm("mut t.keys[at]", "int", "            t.ints[n] = at\n"), "E_SINGLE_OWNER_OVERLAP", "'t' is written by a `match mut` arm that is running");
}

/// F-49's program with `ARM` as the body of the `case Some(step):` arm of `match t.step:`.
fn optionFieldArm(comptime arm: []const u8) []const u8 {
    return "record Step:\n    id: str\n    state: str\n\n\nrecord Tally:\n    step: Step?\n\n\n" ++
        "func mark(mut t: Tally, id: str, state: str):\n    match t.step:\n        case Some(step):\n" ++ arm ++
        "        case None:\n            pass\n\n\nfunc main() -> int:\n    return 0\n";
}

// spec-case: SINGLE-OWNER-DIAG-4
test "a match on a place whose arm writes it back names match mut, and only where match mut takes the write (F-49)" {
    const advice = "`match mut t.step:` lets the arm change it: write through the payload binding, which names its place in t.step, " ++
        "and an arm that binds nothing may assign t.step (docs/match-expressions.md, Mutable element matches)";
    // The site's program: the arm stores a changed copy of the matched case back.
    try refusesQuoting(std.testing.allocator, optionFieldArm(
        \\            if step.id == id:
        \\                mut next = copy(step)
        \\                next.state = copy(state)
        \\                t.step = Some(own next)
        \\
    ), "E_SINGLE_OWNER_OVERLAP", advice);
    // Replacing the matched place with another case is refused under `match mut` too, so the message does not offer
    // `match mut`: it names the place written and offers the write after the arm (FR80).
    try refusesQuoting(std.testing.allocator, optionFieldArm(
        \\            if step.id == id:
        \\                t.step = None
        \\
    ), "E_SINGLE_OWNER_OVERLAP", "change 't.step' after it");
    // A local matched and written in an arm that binds nothing, which `match mut` accepts.
    try refusesQuoting(std.testing.allocator,
        \\record Step:
        \\    id: str
        \\
        \\
        \\func fill(mut s: Step?):
        \\    match s:
        \\        case Some(step):
        \\            pass
        \\        case None:
        \\            s = Some(Step(id="n"))
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP", "`match mut s:` lets the arm change it");
}

// spec-case: SINGLE-OWNER-DIAG-4
test "single owner overlap between a record and one of its fields names both arguments and why they overlap" {
    try refusesQuoting(std.testing.allocator,
        \\record State:
        \\    items: int[]
        \\    stack: int[]
        \\
        \\
        \\func rebuild(mut state: State, stack: int[]) -> int:
        \\    append(mut state.items, len(stack))
        \\    return len(state.items)
        \\
        \\
        \\func main() -> int:
        \\    mut state = State(items=[], stack=[1, 2])
        \\    return rebuild(mut state, state.stack)
    , "E_SINGLE_OWNER_OVERLAP", "'state.stack' lends a part of 'state' to the call, and the earlier argument 'state' passes 'state' `mut`: the callee may change it while it reads 'state.stack'. " ++
        "Pass a value of its own (`copy(state.stack)`), or pass the record itself `mut` and read it inside the callee");
}

// F-24: an argument that computes a value of its own from a record next to `mut` of that record is accepted (F-S1a-12's
// program); the arguments are evaluated before the call, and the value borrows nothing the callee can change.
test "an argument computed from a record beside the record passed mut is accepted when it borrows nothing" {
    try accepts(std.testing.allocator,
        \\record Builder:
        \\    design: str
        \\    links: str[]
        \\
        \\
        \\func link(mut self: Builder, file: str):
        \\    append(mut self.links, copy(file))
        \\
        \\
        \\func build(mut self: Builder, suffix: str):
        \\    link(mut self, self.design + suffix)
        \\
        \\
        \\func main() -> int:
        \\    mut builder = Builder(design="d", links=[])
        \\    build(mut builder, ".x")
        \\    return len(builder.links)
    );
}

/// FR67: the record and the `own` parameter of `keep` and `note`, for the tests below.
const own_beside_mut_header =
    \\record Item:
    \\    n: int
    \\    tag: str
    \\
    \\
    \\record Run:
    \\    pending: Item[]
    \\    files: int
    \\    name: str
    \\
    \\
    \\func make(n: int) -> Item:
    \\    return Item(n=n, tag="x")
    \\
    \\
    \\func note(mut totals: Run, own event: Item):
    \\    append(mut totals.pending, own event)
    \\
    \\
    \\func keep(mut totals: Run, own text: str):
    \\    totals.name = own text
    \\
    \\
    \\func pick(r: Run) -> str from r:
    \\    return r.name
    \\
    \\
;

// FR67: a value of its own made from a record, given to an `own` parameter beside `mut` of that record, is judged as a
// read argument is (F-24): the read ends when the value is made, and the callee owns a value that shares nothing with it.
test "a fresh value made from a record goes to an own parameter beside the record passed mut" {
    try accepts(std.testing.allocator, own_beside_mut_header ++
        \\func main() -> int:
        \\    mut state = Run(pending=[], files=3, name="n")
        \\    keep(mut state, copy(state.name))
        \\    keep(mut state, "a" + state.name)
        \\    keep(mut state, f"{state.files}")
        \\    keep(mut state, copy(pick(state)))
        \\    note(mut state, make(state.files + 1))
        \\    note(mut state, Item(n=state.files, tag=copy(state.name)))
        \\    return len(state.pending)
    );
}

// FR67: a move of a part of the record, or a value that borrows it, stays refused beside `mut` of the record, with the
// refusal the read meets without the deferral.
test "an own argument that moves or borrows a part of the record passed mut is still refused (takenValueBesideMut, deferredConflict)" {
    try refusesQuoting(std.testing.allocator, own_beside_mut_header ++
        \\func main() -> int:
        \\    mut state = Run(pending=[], files=3, name="n")
        \\    keep(mut state, own state.name)
        \\    return len(state.pending)
    , "E_SINGLE_OWNER_OVERLAP", "'own state.name' reads 'state', which the earlier argument 'state' passes `mut`");
    try refusesQuoting(std.testing.allocator, own_beside_mut_header ++
        \\func main() -> int:
        \\    mut state = Run(pending=[], files=3, name="n")
        \\    keep(mut state, pick(state))
        \\    return len(state.pending)
    , "E_SINGLE_OWNER_OVERLAP", "'state' reads 'state', which the earlier argument 'state' passes `mut`");
    try refusesQuoting(std.testing.allocator, own_beside_mut_header ++
        \\func main() -> int:
        \\    mut state = Run(pending=[], files=3, name="n")
        \\    keep(mut state, state.name)
        \\    return len(state.pending)
    , "E_SINGLE_OWNER_OVERLAP", "'state.name' reads 'state', which the earlier argument 'state' passes `mut`");
}

test "F6 undeclared return points at the first return with a missing lender" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        // migrate-embedded: skip intentional F6 partially declared return contract.
        \\func choose(a: int[], b: int[], c: bool) -> int[] from a:
        \\    if c:
        \\        return a
        \\    return b
        \\func main() -> int:
        \\    return 0
    ;
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_BORROW_UNDECLARED", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R4, failure.rule.?);
    try std.testing.expectEqual(@as(usize, 4), unit.src.?.locate(failure.span.start).line);
    try std.testing.expectEqualStrings("b", unit.src.?.text(failure.span));
    try std.testing.expect(failure.repair == .explicit_fix);
    try std.testing.expectEqual(@as(usize, 1), failure.repair.explicit_fix.len);
    const edit = failure.repair.explicit_fix[0];
    const fixed = try std.mem.concat(a, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    const after = try support.checkSource(a, fixed);
    try std.testing.expect(after.passed);
    failure = .{};
    try unique.checkWithSource(a, after.program.?, after.src.?, &failure);
}

// spec-case: BIND-OR-ELSE-5
test "a bind-or-else holds its place until the last use of the name, as a const alias of it would" {
    try accepts(std.testing.allocator,
        \\func f() -> int:
        \\    mut maybe: int[]? = Some([1, 2, 3])
        \\    const items = maybe else:
        \\        return 0
        \\    const size = len(items)
        \\    maybe = None
        \\    return size
        \\
        \\
        \\func main() -> int:
        \\    return f()
    );
    try refusesRelated(std.testing.allocator,
        \\func f() -> int:
        \\    mut maybe: int[]? = Some([1, 2, 3])
        \\    const items = maybe else:
        \\        return 0
        \\    maybe = None
        \\    return len(items)
        \\
        \\
        \\func main() -> int:
        \\    return f()
    , "E_SINGLE_OWNER_OVERLAP", "'maybe' cannot be changed or moved while 'items' borrows it", "borrowed by this binding");
}

// spec-case: BIND-OR-ELSE-6
test "a writable bind-or-else over a borrowed place is refused and over an owned source is accepted" {
    try refusesContaining(std.testing.allocator,
        \\func f(maybe: int[]?) -> int:
        \\    mut items = maybe else:
        \\        return 0
        \\    append(mut items, 1)
        \\    return len(items)
        \\
        \\
        \\func main() -> int:
        \\    return f(Some([1]))
    , "E_SINGLE_OWNER_BORROW", "write `copy(items)` to keep both");
    try accepts(std.testing.allocator,
        \\func read(n: int) -> int[] fails str:
        \\    if n < 0:
        \\        fail "negative"
        \\    return [n]
        \\
        \\
        \\func f(n: int) -> int:
        \\    mut items = read(n) else Err(_):
        \\        return 0
        \\    append(mut items, 1)
        \\    return len(items)
        \\
        \\
        \\func main() -> int:
        \\    return f(3)
    );
    try accepts(std.testing.allocator,
        \\func f(maybe: int[]?) -> int:
        \\    mut items = copy(maybe) else:
        \\        return 0
        \\    append(mut items, 1)
        \\    return len(items)
        \\
        \\
        \\func main() -> int:
        \\    return f(Some([1]))
    );
}

// The stored-file walk (single_owner_files.zig): hand-built record graphs, because the front end refuses a cycle that reaches a file
// before the ownership contract sees it, and the walk must be sound whatever graph it is given.
fn graphRecord(index: usize, name: []const u8, fields: []const language.typed.Field) language.typed.Record {
    return .{ .id = graphType(index), .name = name, .declaration = .{ .start = 0, .end = 0 }, .fields = fields };
}

fn graphType(index: usize) language.typed.Type {
    return @fromBackingInt(@intCast(language.typed.Type.record_base + index));
}

fn graphField(ty: language.typed.Type) language.typed.Field {
    return .{ .name = "f", .declaration = .{ .start = 0, .end = 0 }, .ty = ty };
}

test "stored-file walk: a call that was refused leaves nothing clear, so a cycle that reaches a file is refused from every entry" {
    // Ring -> Spoke -> Ring is a cycle, and Ring stores a file. The walk from Ring cuts at Ring on the way back through Spoke; marking Spoke
    // clear when its own subtree returned would let the walk from Spoke pass, and it must not.
    const ring = [_]language.typed.Field{ graphField(graphType(1)), graphField(.file) };
    const spoke = [_]language.typed.Field{graphField(graphType(0))};
    const records = [_]language.typed.Record{ graphRecord(0, "Ring", &ring), graphRecord(1, "Spoke", &spoke) };
    var walk = try files.Walk.init(std.testing.allocator, records.len);
    defer walk.deinit();
    try std.testing.expectError(error.StoredFile, walk.supported(&records, graphType(0)));
    try std.testing.expect(walk.marks[0] == .unknown and walk.marks[1] == .unknown);
    try std.testing.expectEqual(@as(usize, 2), walk.entered);
    try std.testing.expectError(error.StoredFile, walk.supported(&records, graphType(1)));
    // The records the first call entered were walked again by the second: a refused call teaches nothing.
    try std.testing.expectEqual(@as(usize, 4), walk.entered);
    try std.testing.expect(walk.marks[0] == .unknown and walk.marks[1] == .unknown);
    try std.testing.expectError(error.StoredFile, walk.supported(&records, graphType(0)));
}

test "stored-file walk: a call that returned marks every record it entered clear, and a later call does not walk them again" {
    // A <-> B is a cycle, C hangs off B, D reaches B and a fresh E. The walk from A is cut at A on the way back through B and still
    // returns: B and C are clear, and so is A.
    const a_fields = [_]language.typed.Field{graphField(graphType(1))};
    const b_fields = [_]language.typed.Field{ graphField(graphType(0)), graphField(graphType(2)) };
    const c_fields = [_]language.typed.Field{graphField(.i64)};
    const d_fields = [_]language.typed.Field{ graphField(graphType(1)), graphField(graphType(4)) };
    const e_fields = [_]language.typed.Field{graphField(.bool)};
    const records = [_]language.typed.Record{
        graphRecord(0, "A", &a_fields),
        graphRecord(1, "B", &b_fields),
        graphRecord(2, "C", &c_fields),
        graphRecord(3, "D", &d_fields),
        graphRecord(4, "E", &e_fields),
    };
    var walk = try files.Walk.init(std.testing.allocator, records.len);
    defer walk.deinit();
    try walk.supported(&records, graphType(0));
    try std.testing.expectEqual(@as(usize, 3), walk.entered);
    try std.testing.expect(walk.marks[0] == .clear and walk.marks[1] == .clear and walk.marks[2] == .clear);
    try std.testing.expect(walk.marks[3] == .unknown and walk.marks[4] == .unknown);
    // A type inside the cycle, and the one already walked: no record is entered.
    try walk.supported(&records, graphType(1));
    try walk.supported(&records, graphType(0));
    try std.testing.expectEqual(@as(usize, 3), walk.entered);
    // D enters D and E, and stops at the clear B.
    try walk.supported(&records, graphType(3));
    try std.testing.expectEqual(@as(usize, 5), walk.entered);
    try std.testing.expect(walk.marks[3] == .clear and walk.marks[4] == .clear);
}

test "stored-file walk: a file at the top of a type is allowed and a file below it is not, however the type was reached before" {
    // Holder stores a file; Wrap stores a Plain and a Holder; Plain stores nothing. Wrap's refused call enters Plain and teaches nothing
    // about it; a call of Plain's own then marks it clear.
    const holder = [_]language.typed.Field{graphField(.text_file)};
    const wrap = [_]language.typed.Field{ graphField(graphType(2)), graphField(graphType(0)) };
    const plain = [_]language.typed.Field{graphField(.i64)};
    const records = [_]language.typed.Record{ graphRecord(0, "Holder", &holder), graphRecord(1, "Wrap", &wrap), graphRecord(2, "Plain", &plain) };
    var walk = try files.Walk.init(std.testing.allocator, records.len);
    defer walk.deinit();
    try walk.supported(&records, .text_file);
    try std.testing.expectError(error.StoredFile, walk.supported(&records, graphType(1)));
    try std.testing.expectError(error.StoredFile, walk.supported(&records, graphType(0)));
    try walk.supported(&records, graphType(2));
    try std.testing.expect(walk.marks[2] == .clear and walk.marks[0] == .unknown and walk.marks[1] == .unknown);
}

/// The walk `files.Walk` replaced: a path of the records above, and no memory of an earlier call. What a record stores is read from
/// `typed.Record.eachStored`, as the walk does, so the two differ only in memory.
fn walkBefore(a: std.mem.Allocator, records: []const language.typed.Record, path: *std.ArrayList(language.typed.Type), ty: language.typed.Type, depth: usize) error{ OutOfMemory, StoredFile }!void {
    if (depth != 0 and ty.isFile()) return error.StoredFile;
    if (!ty.isAggregate() or std.mem.indexOfScalar(language.typed.Type, path.items, ty) != null) return;
    try path.append(a, ty);
    defer _ = path.pop();
    try records[ty.recordIndex()].eachStored(error{ OutOfMemory, StoredFile }, Below{ .allocator = a, .records = records, .path = path, .depth = depth + 1 }, Below.visit);
}

/// The walk of one record's stored types for `walkBefore`: where it is, and how deep.
const Below = struct {
    allocator: std.mem.Allocator,
    records: []const language.typed.Record,
    path: *std.ArrayList(language.typed.Type),
    depth: usize,

    fn visit(self: Below, ty: language.typed.Type, _: language.source.Span) error{ OutOfMemory, StoredFile }!void {
        try walkBefore(self.allocator, self.records, self.path, ty, self.depth);
    }
};

/// Whether a walk refused: a stored file is the answer `true`, running out of memory is an error.
fn storedFile(result: error{ OutOfMemory, StoredFile }!void) error{OutOfMemory}!bool {
    result catch |err| switch (err) {
        error.StoredFile => return true,
        error.OutOfMemory => return error.OutOfMemory,
    };
    return false;
}

/// The records of a program and four that store an open file, which the front end would refuse and so no source can show the walk: a
/// record of a text file, a record of a plain record of the program and of that one, a generic wrapper of a file, and a callback that takes one.
fn withStoredFiles(a: std.mem.Allocator, own: []const language.typed.Record) ![]const language.typed.Record {
    const typed = language.typed;
    const span: language.source.Span = .{ .start = 0, .end = 0 };
    const out = try a.alloc(typed.Record, own.len + 4);
    @memcpy(out[0..own.len], own);
    const holder: typed.Type = @fromBackingInt(typed.Type.record_base + own.len);
    const wrapped: typed.Type = @fromBackingInt(typed.Type.record_base + own.len + 1);
    const envelope: typed.Type = @fromBackingInt(typed.Type.record_base + own.len + 2);
    const callback: typed.Type = @fromBackingInt(typed.Type.record_base + own.len + 3);
    out[own.len] = .{ .id = holder, .name = "Holder", .declaration = span, .fields = try a.dupe(typed.Field, &.{.{ .name = "file", .declaration = span, .ty = .text_file }}) };
    out[own.len + 1] = .{ .id = wrapped, .name = "Wrap", .declaration = span, .fields = try a.dupe(typed.Field, &.{
        .{ .name = "plain", .declaration = span, .ty = own[own.len - 1].id },
        .{ .name = "holder", .declaration = span, .ty = holder },
    }) };
    out[own.len + 2] = .{ .id = envelope, .name = "Envelope[File]", .declaration = span, .fields = try a.dupe(typed.Field, &.{.{ .name = "value", .declaration = span, .ty = .file }}) };
    out[own.len + 3] = .{ .id = callback, .name = "Callback", .declaration = span, .fields = &.{}, .contract = .{ .callback = .{ .parameters = &.{.file}, .return_type = .i64 } } };
    return out;
}

/// How many records a program has and how many the walk refuses; every record is asked, forward and then backward, through one shared
/// set of marks, and each answer must be the one the walk it replaced gives with no memory at all. `with_files` adds the four records
/// of `withStoredFiles` to the program's own.
fn walkAgrees(backing: std.mem.Allocator, source: []const u8, with_files: bool) !struct { records: usize, refused: usize } {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const own = (try checked(arena.allocator(), source)).records;
    const records = if (with_files) try withStoredFiles(arena.allocator(), own) else own;
    var path: std.ArrayList(language.typed.Type) = .empty;
    defer path.deinit(backing);
    var walk = try files.Walk.init(backing, records.len);
    defer walk.deinit();
    var refused: usize = 0;
    for (0..2) |pass| for (0..records.len) |step| {
        const index = if (pass == 0) step else records.len - 1 - step;
        const before = try storedFile(walkBefore(backing, records, &path, records[index].id, 0));
        try std.testing.expectEqual(before, try storedFile(walk.supported(records, records[index].id)));
        if (pass == 0 and before) refused += 1;
    };
    return .{ .records = records.len, .refused = refused };
}

test "stored-file walk: with one set of marks shared by every record it answers as the walk it replaced did on real programs" {
    const stored = try walkAgrees(std.testing.allocator,
        \\record Leaf:
        \\    n: int
        \\
        \\
        \\record Tree:
        \\    leaf: Leaf
        \\    kids: Tree[]
        \\    next: Tree?
        \\
        \\
        \\record Envelope[T]:
        \\    value: T
        \\
        \\
        \\func a(tree: Tree, leaf: Envelope[Leaf]) -> int:
        \\    return 0
        \\
        \\
        \\func b(kept: Envelope[Tree], mapped: dict[str, Tree[]]) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , true);
    try std.testing.expect(stored.records > 8);
    try std.testing.expect(stored.refused >= 3 and stored.refused < stored.records);
    const clear = try walkAgrees(std.testing.allocator,
        \\record Node:
        \\    value: int
        \\    left: Node?
        \\    right: Node?
        \\    labels: dict[str, str[]]
        \\
        \\
        \\func size(node: Node) -> int:
        \\    return node.value
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , false);
    try std.testing.expect(clear.records > 3);
    try std.testing.expectEqual(@as(usize, 0), clear.refused);
}

test "a lent value stored in a set is advised sets.include, and the advice is accepted" {
    const lent =
        \\import sets
        \\record Entry:
        \\    key: str
        \\func names(entries: Entry[]) -> set[str]:
        \\    mut seen: set[str] = set()
        \\    for e in entries:
        \\        sets.add(mut seen, e.key)
        \\    return seen
        \\func main() -> int:
        \\    return len(names([]))
    ;
    try refusesQuoting(std.testing.allocator, lent, "E_SINGLE_OWNER_BORROW", "write `sets.include(mut seen, e.key)` to keep both (it copies `e.key` only when the set does not hold it yet)");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const advised = try std.mem.replaceOwned(u8, a, lent, "sets.add(mut seen, e.key)", "sets.include(mut seen, e.key)");
    const unit = try support.checkSource(a, advised);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try unique.checkWithSource(a, unit.program.?, unit.src.?, &failure);
}

/// Check `source`, which ownership refuses with `code`, and return the failure, its strings in `a`.
fn ownershipFailure(a: std.mem.Allocator, source: []const u8, code: []const u8) !unique.Failure {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    return failure;
}

test "F-11 a case or record built for a comparison says so and names the match that needs no copy" {
    const some = "func same(found: str?, wanted: str) -> bool:\n    return found == Some(wanted)\nfunc main() -> int:\n    return 0\n";
    try refusesQuoting(std.testing.allocator, some, "E_SINGLE_OWNER_BORROW", "the `Some(...)` built for this comparison needs its own value; match on the other side");
    const ok = "func same(r: Result[str, int], wanted: str) -> bool:\n    return r == Ok(wanted)\nfunc main() -> int:\n    return 0\n";
    try refusesQuoting(std.testing.allocator, ok, "E_SINGLE_OWNER_BORROW", "(`case Ok(found): found == ...`)");
    const record = "record Tag:\n    name: str\nfunc same(t: Tag, wanted: str) -> bool:\n    return t == Tag(name=wanted)\nfunc main() -> int:\n    return 0\n";
    try refusesQuoting(std.testing.allocator, record, "E_SINGLE_OWNER_BORROW", "the `Tag(...)` built for this comparison needs its own value; compare the other side's fields");
    // Bound to a local, the comparison still keeps nothing: the message is the same, not the local's.
    const bound = "func same(found: str?, wanted: str) -> bool:\n    const s = found == Some(wanted)\n    return s\nfunc main() -> int:\n    return 0\n";
    try refusesQuoting(std.testing.allocator, bound, "E_SINGLE_OWNER_BORROW", "built for this comparison");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const matched = "func same(found: str?, wanted: str) -> bool:\n    match found:\n        case Some(value):\n" ++
        "            return value == wanted\n        case None:\n            return False\nfunc main() -> int:\n    return 0\n";
    try accepts(arena.allocator(), matched);
}

test "F-47 a match on a call that lends from the replaced local names the copy of the matched value" {
    const walk =
        \\import json
        \\func at(value: json.Json, path: str[]) -> json.Json:
        \\    mut here = copy(value)
        \\    for key in path:
        \\        match json.get(here, key):
        \\            case Some(found):
        \\                here = copy(found)
        \\            case None:
        \\                return here
        \\    return here
        \\func main() -> int:
        \\    return 0
    ;
    try refusesQuoting(std.testing.allocator, walk, "E_SINGLE_OWNER_OVERLAP", "copy the matched value first (`match copy(json.get(here, key)):`)");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const advised = try std.mem.replaceOwned(u8, a, try std.mem.replaceOwned(u8, a, walk, "match json.get(here, key):", "match copy(json.get(here, key)):"), "here = copy(found)", "here = own found");
    try accepts(a, advised);
}

test "F-37 a change of a record while a with scope opened from its capability field is open names the scope and the copy" {
    const scoped =
        \\import network
        \\record Holder:
        \\    net: Network
        \\    count: int
        \\    names: str[]
        \\func bump(mut holder: Holder):
        \\    holder.count += 1
        \\func run(mut holder: Holder) -> int:
        \\    with holder.net.host("127.0.0.1:1") as scoped:
        \\        bump(mut holder)
        \\    return holder.count
        \\func main(net: Network) -> int:
        \\    mut holder = Holder(net=net, count=0, names=[])
        \\    return run(mut holder)
    ;
    try refusesQuoting(std.testing.allocator, scoped, "E_SINGLE_OWNER_OVERLAP", "'holder' cannot be changed while the `with` scope opened from `holder.net` is open");
    try refusesQuoting(std.testing.allocator, scoped, "E_SINGLE_OWNER_OVERLAP", "write `const handle = copy(holder.net)` before the `with`");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepts(a, try std.mem.replaceOwned(u8, a, scoped, "    with holder.net.host(", "    const handle = copy(holder.net)\n    with handle.host("));
}

test "F-44 recordFields notes the one owned field of a record of borrows where a borrowed record would be read in place" {
    const head =
        \\record Inner:
        \\    name: str
        \\record Row:
        \\    id: str
        \\    extra: Inner?
        \\record Source:
        \\    id: str
        \\func keep(mut found: Row[], row: Row):
        \\    append(mut found, copy(row))
        \\
    ;
    const tail = "func main() -> int:\n    return 0\n";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const argument = head ++ "func g(mut found: Row[], source: Source, inner: Inner):\n    keep(mut found, Row(id=source.id, extra=Some(copy(inner))))\n" ++ tail;
    const read = try ownershipFailure(a, argument, "E_SINGLE_OWNER_BORROW");
    try std.testing.expect(read.notes.cause != null);
    try std.testing.expect(std.mem.indexOf(u8, read.notes.cause.?.message, "field `extra` holds an owned value, so `Row(...)` owns its fields") != null);
    // Appended, the record is stored: a record of borrows is refused there too, so no note blames `extra`.
    const stored = head ++ "func g(mut found: Row[], source: Source, inner: Inner):\n    append(mut found, Row(id=source.id, extra=Some(copy(inner))))\n" ++ tail;
    const kept = try ownershipFailure(a, stored, "E_SINGLE_OWNER_BORROW");
    try std.testing.expect(kept.notes.cause == null);
}

test "F-15 F-8 keepingCaller makes an undeclared borrowed return offer from when no caller keeps the result and the copy when one does" {
    const head = "record Ward:\n    url: str\nfunc label(status: str) -> str:\n    if status == \"\":\n        return \"none\"\n    return status\n";
    const reads = head ++ "func main() -> int:\n    return len(label(\"a\"))\n";
    try refusesQuoting(std.testing.allocator, reads, "E_BORROW_UNDECLARED", "declare the result `from status`: no caller in the program keeps the result");
    const keeps = head ++ "func ward(text: str) -> Ward:\n    const url = label(text)\n    return Ward(url=own url)\n" ++
        "func main() -> int:\n    return len(ward(\"a\").url)\n";
    try refusesQuoting(std.testing.allocator, keeps, "E_BORROW_UNDECLARED", "write `copy(status)` to keep both: `ward` keeps the result");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const failure = try ownershipFailure(arena.allocator(), keeps, "E_BORROW_UNDECLARED");
    // The repair is the copy of the borrowed return, not a `from` clause.
    try std.testing.expectEqual(@as(usize, 1), failure.copy.borrowed.len);
    try std.testing.expect(failure.repair == .none);
}

test "F-8 keepingCallerOf and keepingCallerIn name the caller that keeps a result and none for one that only reads it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Ward:
        \\    url: str
        \\func label(status: str) -> str:
        \\    if status == "":
        \\        return "none"
        \\    return copy(status)
        \\func reads(text: str) -> int:
        \\    return len(label(text))
        \\func ward(text: str) -> Ward:
        \\    const url = label(text)
        \\    return Ward(url=own url)
        \\func main() -> int:
        \\    return reads("a") + len(ward("b").url)
    ;
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    const program = unit.program.?;
    const label = indexOfFunction(program, "label").?;
    const keeper = (try unique.keepingCallerOf(a, program, unit.src.?, label, &.{0})).?;
    try std.testing.expectEqualStrings("ward", program.functions[keeper].name);
    // Without `ward`, the one caller only reads the result.
    const reader = try support.checkSource(a, "func label(status: str) -> str:\n    return copy(status)\nfunc main() -> int:\n    return len(label(\"a\"))\n");
    const alone = indexOfFunction(reader.program.?, "label").?;
    try std.testing.expect(try unique.keepingCallerOf(a, reader.program.?, reader.src.?, alone, &.{0}) == null);
}

/// A function that stores a copy of `name`, and callers that pass it a name: an `own` parameter, an owned local at its last
/// use, and (in `copy_for_store_reads_again`) an owned local read again after the call.
const copy_for_store_callers =
    \\record Row:
    \\    name: str
    \\    size: int
    \\func make_row(name: str, size: int) -> Row:
    \\    return Row(name=copy(name), size=size)
    \\func handed(own label: str) -> Row:
    \\    return make_row(label, 2)
    \\func last(n: int) -> Row:
    \\    const text = f"a{n}"
    \\    return make_row(text, n)
    \\
;

const copy_for_store_reads_again =
    \\func again(n: int) -> int:
    \\    const word = f"b{n}"
    \\    const row = make_row(word, n)
    \\    return row.size + len(word)
    \\func main() -> int:
    \\    return handed("x").size + last(1).size + again(2)
;

test "COPY-A3c the W_COPY_FOR_STORE judge accepts an own parameter or a last-use local with an own mark, and withholds a name read again" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, copy_for_store_callers ++ copy_for_store_reads_again);
    try std.testing.expect(unit.passed);
    const program = unit.program.?;
    const make_row = indexOfFunction(program, "make_row").?;
    const target: language.semantic_summary.HintTarget = .{ .callee = make_row, .result = false, .position = 0, .store = true };
    const facts = try unique.callerFacts(a, program, unit.src.?, &.{target});
    try std.testing.expectEqual(@as(usize, 3), facts[0].len);
    for (facts[0]) |fact| {
        const again = std.mem.endsWith(u8, program.functions[fact.caller].name, "again");
        try std.testing.expectEqual(again, fact.keeps);
    }
    // The argument half marks all three names; the ownership half withholds the repair for `again`.
    const marks = (try language.copy_for_store.callersAccept(a, program, make_row, 0)).?;
    try std.testing.expectEqual(@as(usize, 3), marks.len);
    try std.testing.expectEqualStrings("word", unit.src.?.text(.{ .start = marks[2], .end = marks[2] + 4 }));
}

test "COPY-A3c the W_COPY_FOR_STORE repair with its own marks leaves a program that checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const main = "func main() -> int:\n    return handed(\"x\").size + last(1).size\n";
    const unit = try support.checkSource(a, copy_for_store_callers ++ main);
    try std.testing.expect(unit.passed);
    const program = unit.program.?;
    const make_row = indexOfFunction(program, "make_row").?;
    const target: language.semantic_summary.HintTarget = .{ .callee = make_row, .result = false, .position = 0, .store = true };
    const facts = try unique.callerFacts(a, program, unit.src.?, &.{target});
    for (facts[0]) |fact| try std.testing.expect(!fact.keeps);
    const marks = (try language.copy_for_store.callersAccept(a, program, make_row, 0)).?;
    try std.testing.expectEqual(@as(usize, 2), marks.len);
    const edited = try ownRepaired(a, unit.src.?.bytes, marks);
    try std.testing.expect(std.mem.indexOf(u8, edited, "make_row(own text, n)") != null);
    try std.testing.expect(std.mem.indexOf(u8, edited, "make_row(own label, 2)") != null);
    const repaired = try support.checkSource(a, edited);
    try std.testing.expect(repaired.passed);
}

/// `text` with the `W_COPY_FOR_STORE` repair of `make_row(name: ...)` applied by hand: `own ` before the parameter, `own name`
/// for its copy, and `own ` at each of two caller marks after them.
fn ownRepaired(a: std.mem.Allocator, text: []const u8, marks: []const u32) ![]const u8 {
    var edited: std.ArrayList(u8) = .empty;
    var from: usize = 0;
    const signature = std.mem.indexOf(u8, text, "name: str, size").?;
    const body = std.mem.indexOf(u8, text, "copy(name)").?;
    const cuts = [_]usize{ signature, body, marks[0], marks[1] };
    for (cuts, 0..) |cut, at| {
        try edited.appendSlice(a, text[from..cut]);
        try edited.appendSlice(a, if (at == 1) "own name" else "own ");
        from = if (at == 1) cut + "copy(name)".len else cut;
    }
    try edited.appendSlice(a, text[from..]);
    return edited.items;
}

const match_mut_loop_head =
    \\enum Slot:
    \\    Dict(value: dict[str, int])
    \\    Words(items: str[])
    \\    Empty
    \\
    \\func peek(slot: Slot) -> bool:
    \\    match slot:
    \\        case Empty:
    \\            return True
    \\        case Dict(value):
    \\            return False
    \\        case Words(items):
    \\            return False
    \\
    \\func work(out: Stream, mut slot: Slot):
    \\    match mut slot:
    \\        case Dict(value):
    \\            print(out, "dict")
    \\        case Empty:
    \\            print(out, "empty")
    \\        case Words(items):
    \\
;

fn matchMutLoop(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ match_mut_loop_head, body, "\nfunc main() -> int:\n    return 0\n" });
}

// spec-case: SINGLE-OWNER-DIAG-4
test "a loop over a match mut binding reads its elements, and a change of the binding while they are used is refused (FR25)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The loop variable is a borrow of the binding, which is the place: reading it is reading the binding.
    try accepts(a, try matchMutLoop(a,
        \\            for word in items:
        \\                print(out, word)
        \\            append(mut items, "end")
        \\            for word in items:
        \\                print(out, word)
        \\
    ));
    try accepts(a, try matchMutLoop(a,
        \\            for first in items:
        \\                for second in items:
        \\                    print(out, first == second)
        \\
    ));
    // A change of the binding in a loop over it is refused whether or not the loop variable is read, as for a `mut` local (R7): a
    // list grows under its own loop and a dictionary traps at run time (FR26).
    try refusesQuoting(a, try matchMutLoop(a,
        \\            for word in items:
        \\                append(mut items, "end")
        \\                break
        \\
    ), "E_SINGLE_OWNER_OVERLAP", "while another argument or iteration borrows it");
    // A change while the loop variable is used in the loop is refused, as the same loop over a `mut` local is (R7).
    const advice = "is changed here while 'word', a borrow of its contents, is still used";
    try refusesQuoting(a, try matchMutLoop(a,
        \\            for word in items:
        \\                append(mut items, "end")
        \\                print(out, word)
        \\
    ), "E_SINGLE_OWNER_OVERLAP", advice);
    try refusesQuoting(a, try matchMutLoop(a,
        \\            for word in items:
        \\                print(out, word)
        \\                items[0] = "x"
        \\
    ), "E_SINGLE_OWNER_OVERLAP", advice);
    // The matched owner itself is still not readable beside the arm's binding.
    try refusesQuoting(a, try matchMutLoop(a,
        \\            for word in items:
        \\                print(out, peek(slot))
        \\                print(out, word)
        \\
    ), "E_SINGLE_OWNER_OVERLAP", "is written by a `match mut` arm that is running");
}

// spec-case: SINGLE-OWNER-DIAG-4
test "exchange and take of an element of a match mut binding write through the place, and a loop over the binding still refuses them (FR27, R7)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The binding is a name for its place: an element of it is written through that place by `items[0] = v` and by
    // `lists.exchange`, and now by the builtins, which stage the element in a compiler temporary of their own.
    try accepts(a, try matchMutLoop(a,
        \\            const old = exchange(mut items[0], "z")
        \\            const taken = take(mut items[1])
        \\            print(out, old + taken + items[0] + items[1])
        \\            append(mut items, "end")
        \\
    ));
    try accepts(a, try matchMutLoop(a,
        \\            items[0] = "x"
        \\            _ = exchange(mut items[1], "y")
        \\            print(out, items[0])
        \\
    ));
    // The matched owner itself is still not readable beside the arm's binding, and a change while a loop walks the binding is
    // refused whether or not the loop variable is read, as for a `mut` local (R7).
    try refusesQuoting(a, try matchMutLoop(a,
        \\            const old = exchange(mut items[0], "z")
        \\            print(out, peek(slot))
        \\            print(out, old + items[0])
        \\
    ), "E_SINGLE_OWNER_OVERLAP", "is written by a `match mut` arm that is running");
    try refusesQuoting(a, try matchMutLoop(a,
        \\            for word in items:
        \\                _ = exchange(mut items[0], "z")
        \\                break
        \\
    ), "E_SINGLE_OWNER_OVERLAP", "while another argument or iteration borrows it");
    try refusesQuoting(a, try matchMutLoop(a,
        \\            for word in items:
        \\                _ = take(mut items[0])
        \\                break
        \\
    ), "E_SINGLE_OWNER_OVERLAP", "while another argument or iteration borrows it");
    try refusesQuoting(a, try matchMutLoop(a,
        \\            for word in items:
        \\                print(out, word)
        \\                _ = exchange(mut items[0], "z")
        \\
    ), "E_SINGLE_OWNER_OVERLAP", "is changed here while 'word', a borrow of its contents, is still used");
    // A change after the loop is accepted.
    try accepts(a, try matchMutLoop(a,
        \\            for word in items:
        \\                print(out, word)
        \\            _ = exchange(mut items[0], "z")
        \\
    ));
}

// spec-case: SINGLE-OWNER-DIAG-4
test "two writes through one match mut binding in one arm build and run as on a mut local; a field of an element is written in place (FX17)" {
    // The binding is a name for its place: a write whose receiver is the binding (`lists.exchange`, `lists.pop`) after a
    // finished write through a temporary staged from it (`recs[0] = v`, the builtins) is not a write in flight (Z3), and an
    // element's managed field is written into the payload read it was read through.
    try executes(std.testing.allocator,
        \\import lists
        \\record Rec:
        \\    text: str
        \\enum Slot:
        \\    Recs(recs: Rec[])
        \\    Empty
        \\func work(mut slot: Slot) -> str:
        \\    mut seen = ""
        \\    match mut slot:
        \\        case Recs(recs):
        \\            recs[0] = Rec(text="assigned")
        \\            const other = lists.exchange(mut recs, 1, Rec(text="second"))
        \\            const old = exchange(mut recs[0], Rec(text="swapped"))
        \\            append(mut recs, Rec(text="tail"))
        \\            recs[2].text = "field"
        \\            const last = lists.pop(mut recs)
        \\            seen = other.text + "|" + old.text + "|" + last.text + "|" + recs[0].text + "|" + recs[1].text
        \\        case Empty:
        \\            seen = "empty"
        \\    return seen
        \\func main(out: Stream) -> int:
        \\    mut b = Slot.Recs(recs=[Rec(text="r0"), Rec(text="r1")])
        \\    print(out, work(mut b))
        \\    return 0
    , "r1|assigned|field|swapped|second\n");
}

// spec-case: SINGLE-OWNER-DIAG-4
test "a returned slice of a byte_buffer parameter is told to copy it or return its octets as bytes, never to declare the buffer result from (FX17)" {
    // A `byte_buffer` result cannot be declared `from` a parameter, so the `from` advice (and the edit `selka fix` made of
    // it) could not be followed; the copy can, and `bytes(...)` gives the octets for a `bytes` result.
    const source =
        \\func middle(buf: byte_buffer) -> byte_buffer:
        \\    return buf[1:3]
        \\func main(out: Stream) -> int:
        \\    print(out, middle(byte_buffer([97, 98, 99, 100])))
        \\    return 0
    ;
    const advice = "write `copy(buf[1:3])` to keep both: a `byte_buffer` result cannot be declared `from` a parameter; " ++
        "for the octets alone, return `bytes(buf[1:3])` from a function whose result is `bytes`";
    try refusesQuoting(std.testing.allocator, source, "E_BORROW_UNDECLARED", advice);
    // A `bytes` result keeps the `from` advice.
    try refusesQuoting(std.testing.allocator,
        \\func middle(data: bytes) -> bytes:
        \\    return data[1:3]
        \\func main(out: Stream) -> int:
        \\    print(out, middle(b"abcd"))
        \\    return 0
    , "E_BORROW_UNDECLARED", "declare the result `from data`");
}

/// A function whose `match mut` arms bind a dictionary, a set and a list of text, with `BODY` lines at the arms' depth (FR26).
fn matchMutCollections(a: std.mem.Allocator, dict_body: []const u8, set_body: []const u8, list_body: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{
        "import sets\n\n\nenum Slot:\n    Dict(value: dict[str, int])\n    Tags(tags: set[str])\n    Words(items: str[])\n    Empty\n\n\n",
        "func work(out: Stream, mut slot: Slot):\n    match mut slot:\n        case Dict(value):\n",
        dict_body,
        "        case Tags(tags):\n",
        set_body,
        "        case Words(items):\n",
        list_body,
        "        case Empty:\n            print(out, \"empty\")\n\n\nfunc main() -> int:\n    return 0\n",
    });
}

const reads_only =
    \\            print(out, "reads")
    \\
;

// spec-case: SINGLE-OWNER-DIAG-4
test "a loop over a match mut binding refuses a change of the collection it walks, as the loop over a mut local does (FR26, R7)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const code = "E_SINGLE_OWNER_OVERLAP";
    const advice = "while another argument or iteration borrows it";
    // A list grows under its own loop, a dictionary traps at run time, and a set changes under the walk: all three are refused.
    try refusesQuoting(a, try matchMutCollections(a,
        \\            for key in value:
        \\                value["z"] = 1
        \\
    , reads_only, reads_only), code, advice);
    try refusesQuoting(a, try matchMutCollections(a, reads_only,
        \\            for tag in tags:
        \\                sets.add(mut tags, "z")
        \\
    , reads_only), code, advice);
    try refusesQuoting(a, try matchMutCollections(a, reads_only, reads_only,
        \\            for word in items:
        \\                append(mut items, "z")
        \\
    ), code, advice);
    // The same loop nested, and in the body of an `if` with a read of the loop variable: the loop variable is used again, so the
    // refusal is the older one that names it.
    try refusesQuoting(a, try matchMutCollections(a, reads_only, reads_only,
        \\            for first in items:
        \\                for second in items:
        \\                    if first == second:
        \\                        append(mut items, "z")
        \\
    ), code, "is changed here while");
    try refusesQuoting(a, try matchMutCollections(a, reads_only, reads_only,
        \\            for word in items:
        \\                print(out, word)
        \\                if len(word) > 1:
        \\                    append(mut items, "z")
        \\
    ), code, "is changed here while");
    // A change after the loop, a change in a loop over another collection, and reads in a nested loop stay accepted.
    try accepts(a, try matchMutCollections(a,
        \\            for key in value:
        \\                print(out, key)
        \\            value["z"] = 1
        \\
    ,
        \\            for tag in tags:
        \\                print(out, tag)
        \\            sets.add(mut tags, "z")
        \\
    ,
        \\            for word in items:
        \\                for other in items:
        \\                    print(out, word == other)
        \\            append(mut items, "z")
        \\            for word in items:
        \\                print(out, word)
        \\
    ));
    try accepts(a, try matchMutCollections(a, reads_only, reads_only,
        \\            mut extra: str[] = []
        \\            for word in items:
        \\                append(mut extra, copy(word))
        \\            print(out, len(extra))
        \\
    ));
}

/// The index of the function named `name` (its last segment) in `program`.
fn indexOfFunction(program: language.typed.Program, name: []const u8) ?usize {
    for (program.functions, 0..) |function, index| {
        if (std.mem.endsWith(u8, function.name, name)) return index;
    }
    return null;
}

/// Check `source`, which ownership refuses with `code` and the message `ending`, and which names no form without a copy.
fn refusesWithCopyAlone(backing: std.mem.Allocator, source: []const u8, code: []const u8, ending: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (!std.mem.endsWith(u8, failure.message, ending)) report("unexpected message: {s}\n", .{failure.message});
    try std.testing.expect(std.mem.endsWith(u8, failure.message, ending));
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "declare `") == null);
    try std.testing.expect(failure.copy.span != null);
}

/// Check that `source` is refused with the message `advice`, and that `advised`, the program written as that message tells, passes.
fn refusesWithTakeForm(backing: std.mem.Allocator, source: []const u8, advice: []const u8, advised: []const u8) !void {
    try refusesQuoting(backing, source, "E_SINGLE_OWNER_BORROW", advice);
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, advised);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try unique.checkWithSource(a, unit.program.?, unit.src.?, &failure);
}

test "COPY-B1 a plain parameter stored bare is told the own form first and the copy second, when that form checks" {
    const row =
        \\record Row:
        \\    name: str
        \\    count: int
        \\
        \\
    ;
    const callers = "\n\nfunc main() -> int:\n    return len(make(\"a\").name)\n";
    // A whole parameter stored in a field the function returns.
    try refusesWithTakeForm(std.testing.allocator, row ++
        \\func make(name: str) -> Row:
        \\    return Row(name=name, count=1)
    ++ callers, "a bare `name` only lends the plain parameter `name`, and field `name` of `Row` would keep it after the call returns; " ++
        "declare `name` as `own name: str` and write `own name` here to take it (a caller then gives it with `own name`, " ++
        "or copies if it reads it again), or write `copy(name)` to keep both", row ++
        \\func make(own name: str) -> Row:
        \\    return Row(name=own name, count=1)
    ++ callers);
    // A field of a parameter, once the other fields of it are read.
    try refusesWithTakeForm(std.testing.allocator, row ++
        \\func make(other: Row) -> Row:
        \\    const next = other.count + 1
        \\    return Row(name=other.name, count=next)
        \\
        \\
        \\func main() -> int:
        \\    return len(make(Row(name="a", count=1)).name)
    , "`other.name` is lent by the plain parameter `other`, and field `name` of `Row` would keep it after the call returns; " ++
        "declare `other` as `own other: Row` and write `own other.name` here to take it (a caller then gives it with `own other`, " ++
        "or copies if it reads it again), or write `copy(other.name)` to keep both", row ++
        \\func make(own other: Row) -> Row:
        \\    const next = other.count + 1
        \\    return Row(name=own other.name, count=next)
        \\
        \\
        \\func main() -> int:
        \\    return len(make(Row(name="a", count=1)).name)
    );
    // Two parameters in a list: each is told its own form.
    try refusesWithTakeForm(std.testing.allocator,
        \\func pair(a: str, b: str) -> str[]:
        \\    return [a, b]
        \\
        \\
        \\func main() -> int:
        \\    return len(pair("x", "y"))
    , "a bare `a` only lends the plain parameter `a`, and the list needs its own value; declare `a` as `own a: str` and write `own a` here to take it",
        \\func pair(own a: str, own b: str) -> str[]:
        \\    return [own a, own b]
        \\
        \\
        \\func main() -> int:
        \\    return len(pair("x", "y"))
    );
}

test "COPY-B1 a plain parameter that the own form would not check keeps the text that names the copy alone" {
    const row =
        \\record Row:
        \\    name: str
        \\    count: int
        \\
        \\
    ;
    // The parameter is read again after the store: `own name` would move it first.
    try refusesWithCopyAlone(std.testing.allocator, row ++
        \\func make(name: str) -> Row:
        \\    return Row(name=name, count=len(name))
        \\
        \\
        \\func main() -> int:
        \\    return len(make("a").name)
    , "E_SINGLE_OWNER_BORROW", "would keep it after the call returns; write `copy(name)` to keep both");
    // A field of a parameter whose sibling is read after it in the same constructor.
    try refusesWithCopyAlone(std.testing.allocator, row ++
        \\func make(other: Row) -> Row:
        \\    return Row(name=other.name, count=other.count + 1)
        \\
        \\
        \\func main() -> int:
        \\    return len(make(Row(name="a", count=1)).name)
    , "E_SINGLE_OWNER_BORROW", "would keep it after the call returns; write `copy(other.name)` to keep both");
    // A store in a loop: `own name` would move the parameter on the first pass.
    try refusesWithCopyAlone(std.testing.allocator,
        \\func many(name: str) -> str[]:
        \\    mut out: str[] = []
        \\    for i in range(3):
        \\        append(mut out, name)
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    return len(many("a"))
    , "E_SINGLE_OWNER_BORROW", "needs its own value; write `copy(name)` to keep both");
    // A `mut` parameter lends the caller's storage exclusively, and is not taken `own` by this advice.
    try refusesWithCopyAlone(std.testing.allocator, row ++
        \\func make(mut name: str) -> Row:
        \\    return Row(name=name, count=1)
        \\
        \\
        \\func main() -> int:
        \\    mut label = "a"
        \\    return len(make(mut label).name)
    , "E_SINGLE_OWNER_BORROW", "would keep it after the call returns; write `copy(name)` to keep both");
    // An element of a loop over a parameter: the loop form is the front end's, so the text is as it was.
    try refusesWithCopyAlone(std.testing.allocator, row ++
        \\func keep(items: Row[]) -> Row[]:
        \\    mut out: Row[] = []
        \\    for item in items:
        \\        if item.count > 1:
        \\            append(mut out, item)
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    return len(keep([]))
    , "E_SINGLE_OWNER_OVERLAP", "copy it with copy(value) or finish the borrow first");
}

test "FR42 own of a field of a @linear owner where the position only reads says the owner stays unconsumed and offers no removal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tail = "func main() -> int:\n    return 0\n";
    const discard = "@linear\nrecord Tx:\n    undo: int[]\n    weight: int\nfunc rollback(own tx: Tx):\n    _ = own tx.undo\n" ++ tail;
    const failure = try ownershipFailure(a, discard, "E_OWN_MARKER");
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "`own tx.undo` gives `tx.undo`, but this position only reads it, so it does not end the `@linear` owner `tx`") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "removing `own` would leave `tx` unconsumed") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "(`const kept = own tx.undo`, `return own tx.undo`) or give `tx` to an `own` parameter") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "; remove `own`") == null);
    try std.testing.expect(failure.repair == .none);
    // An argument that only reads the field, and a field reached through another field: the same owner, the same refusal.
    const argument = "@linear\nrecord Tx:\n    undo: int[]\n    weight: int\nfunc count(xs: int[]) -> int:\n    return len(xs)\n" ++
        "func rollback(own tx: Tx) -> int:\n    return count(own tx.undo)\n" ++ tail;
    const read = try ownershipFailure(a, argument, "E_OWN_MARKER");
    try std.testing.expect(std.mem.indexOf(u8, read.message, "removing `own` would leave `tx` unconsumed") != null);
    try std.testing.expect(read.repair == .none);
    const nested = "record Log:\n    undo: int[]\n@linear\nrecord Tx:\n    log: Log\n    weight: int\nfunc rollback(own tx: Tx):\n    _ = own tx.log.undo\n" ++ tail;
    const through = try ownershipFailure(a, nested, "E_OWN_MARKER");
    try std.testing.expect(std.mem.indexOf(u8, through.message, "`own tx.log.undo` gives `tx.log.undo`") != null);
    try std.testing.expect(through.repair == .none);
    // A record that is not `@linear` keeps its refusal and its removal.
    const plain = "record Tx:\n    undo: int[]\n    weight: int\nfunc rollback(own tx: Tx):\n    _ = own tx.undo\n" ++ tail;
    const old = try ownershipFailure(a, plain, "E_OWN_MARKER");
    try std.testing.expectEqualStrings("`own tx.undo` gives `tx.undo`, but this position only reads it; remove `own`", old.message);
    try std.testing.expect(old.repair == .explicit_fix);
}

test "MSG-C a change of a record while a for loop iterates a list inside it names the field, the detach loop, then the walk by position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // W3-F-7: `for name in st.names:` with `touch(mut st, name)` inside; the repair is a loop over positions, which copies one element.
    const text = "record Store:\n    names: str[]\n    count: int\n\nfunc touch(mut st: Store, name: str):\n    st.count += len(name)\n\n" ++
        "func main() -> int:\n    mut st = Store(names=[\"a\"], count=0)\n    for name in st.names:\n        touch(mut st, name)\n    return st.count\n";
    const failure = try ownershipFailure(a, text, "E_SINGLE_OWNER_OVERLAP");
    try std.testing.expectEqualStrings(
        "'st' cannot be changed here while a `for` loop iterates `st.names`: the loop borrows it until it ends. If the call changes only " ++
            "another field of 'st', pass that field (`mut st.field`). Or write `for name in detach st.names:`, which sets the list aside " ++
            "for the loop and puts it back at every exit; inside the loop `st.names` is empty. Or walk the list by position, which holds " ++
            "no borrow between visits: `mut k = 0`, `while k < len(st.names):`, as its first line `const name = copy(st.names[k])`, " ++
            "which copies the one element, not the list, and `k += 1` as its last",
        failure.message,
    );
    try std.testing.expect(failure.repair == .none);
    // A scalar element is read as it is.
    const scalars = "record Store:\n    ids: int[]\n    count: int\n\nfunc touch(mut st: Store, id: int):\n    st.count += id\n\n" ++
        "func main() -> int:\n    mut st = Store(ids=[1], count=0)\n    for id in st.ids:\n        touch(mut st, id)\n    return st.count\n";
    const plain = try ownershipFailure(a, scalars, "E_SINGLE_OWNER_OVERLAP");
    try std.testing.expect(std.mem.indexOf(u8, plain.message, "as its first line `const id = st.ids[k]`, and `k += 1` as its last") != null);
    // An element's field, as in the entry: the place is written out as the loop spells it, and the element's kind is not guessed.
    const nested = "record Node:\n    deps: int[]\n\nrecord Mf:\n    nodes: Node[]\n\nrecord State:\n    mf: Mf\n    count: int\n\n" ++
        "func touch(mut st: State, dep: int):\n    st.count += dep\n\n" ++
        "func main() -> int:\n    mut st = State(mf=Mf(nodes=[Node(deps=[1])]), count=0)\n    const n = 0\n    for dep in st.mf.nodes[n].deps:\n        touch(mut st, dep)\n    return st.count\n";
    const through = try ownershipFailure(a, nested, "E_SINGLE_OWNER_OVERLAP");
    try std.testing.expect(std.mem.indexOf(u8, through.message, "'st' cannot be changed here while a `for` loop iterates `st.mf.nodes[n].deps`") != null);
    try std.testing.expect(std.mem.indexOf(u8, through.message, "`while k < len(st.mf.nodes[n].deps):`, as its first line `const dep = st.mf.nodes[n].deps[k]`, " ++
        "written `copy(st.mf.nodes[n].deps[k])` for a text, list or record element") != null);
}

/// Check that `source`, with the checker given its text, passes.
fn passesWithSource(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try unique.checkWithSource(a, unit.program.?, unit.src.?, &failure);
}

test "FR57 a slice view that a later write to another field of its record invalidated names the write and the read, and each repair checks" {
    const head = "record Reader:\n    buf: bytes\n    pos: int\n\nfunc show(b: bytes) -> int:\n    return len(b)\n\n";
    const tail = "\n\nfunc main() -> int:\n    mut r = Reader(buf=b\"abc\", pos=0)\n    return next_piece(mut r, 2)\n";
    try refusesQuoting(std.testing.allocator, head ++
        \\func next_piece(mut r: Reader, end: int) -> int:
        \\    const piece = r.buf[r.pos:end]
        \\    r.pos = end + 1
        \\    return show(piece)
    ++ tail, "E_SLICE_ESCAPES", "`piece` is the slice `r.buf[r.pos:end]`, lent by the `mut` parameter `r`, and the write to `r.pos` at line 10, " ++
        "column 5 changes `r` as a whole, so `piece` cannot be read at line 11, column 17; use `piece` before line 10, keep its span " ++
        "(the start and length) and slice again where it is read, or wrap the initializer of `piece` in `copy(...)` to keep both");
    // The repairs, in the order the message names them, each check.
    try passesWithSource(std.testing.allocator, head ++
        \\func next_piece(mut r: Reader, end: int) -> int:
        \\    const piece = r.buf[r.pos:end]
        \\    const n = show(piece)
        \\    r.pos = end + 1
        \\    return n
    ++ tail);
    try passesWithSource(std.testing.allocator, head ++
        \\func next_piece(mut r: Reader, end: int) -> int:
        \\    const start = r.pos
        \\    r.pos = end + 1
        \\    return show(r.buf[start:end])
    ++ tail);
    try passesWithSource(std.testing.allocator, head ++
        \\func next_piece(mut r: Reader, end: int) -> int:
        \\    const piece = copy(r.buf[r.pos:end])
        \\    r.pos = end + 1
        \\    return show(piece)
    ++ tail);
}

test "FR57 a slice view whose source was given away is not told to slice again, and one that a call took mut names the call's argument" {
    try refusesQuoting(std.testing.allocator,
        \\func eat(own s: str) -> int:
        \\    return len(s)
        \\
        \\
        \\func main() -> int:
        \\    const xs = "hello world"
        \\    const piece = xs[0:5]
        \\    const n = eat(own xs)
        \\    return len(piece) + n
    , "E_SLICE_ESCAPES", "`piece` is the slice `xs[0:5]`, lent by the local `xs`, and `xs` is given away at line 8, column 19, " ++
        "so `piece` cannot be read at line 9, column 16; use `piece` before line 8, or wrap the initializer of `piece` in " ++
        "`copy(...)` to keep both");
    const head = "record Reader:\n    buf: bytes\n    pos: int\n\nfunc bump(mut r: Reader) -> int:\n    r.pos = r.pos + 1\n    return r.pos\n\n";
    try refusesQuoting(std.testing.allocator, head ++
        \\func next_piece(mut r: Reader, end: int) -> int:
        \\    const piece = r.buf[r.pos:end]
        \\    const n = bump(mut r)
        \\    return len(piece) + n
        \\
        \\
        \\func main() -> int:
        \\    mut r = Reader(buf=b"abc", pos=0)
        \\    return next_piece(mut r, 2)
    , "E_SLICE_ESCAPES", "and the `mut` argument `r` at line 11, column 20 changes `r`, so `piece` cannot be read at line 12, column 16; " ++
        "use `piece` before line 11, keep its span");
}

/// NARROW-OWN: check `source`, which Core must refuse with `code` and a message holding `fragment`, and return the repair's one
/// edit applied to the source (null when the refusal carries no edit). A repaired source is checked again and must pass.
fn narrowedRefusal(a: std.mem.Allocator, source: []const u8, code: []const u8, fragment: []const u8) !?[]const u8 {
    const unit = try support.checkSource(a, source);
    for (unit.diagnostics) |item| if (!unit.passed) report("{s}: {s}\n", .{ item.code, item.message });
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
    if (failure.repair != .explicit_fix) return null;
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 1), edits.len);
    const repaired = try std.mem.concat(a, u8, &.{ source[0..edits[0].span.start], edits[0].text, source[edits[0].span.end..] });
    const after = try support.checkSource(a, repaired);
    try std.testing.expect(after.passed);
    failure = .{};
    try unique.checkWithSource(a, after.program.?, after.src.?, &failure);
    return repaired;
}

/// The head of the NARROW-OWN programs: a record with a list in it, an option of it, and a function that keeps one.
const narrowed_head =
    \\record Cmd:
    \\    name: str
    \\    args: str[]
    \\
    \\record Inv:
    \\    cmd: Cmd
    \\
    \\func find(name: str) -> Cmd?:
    \\    if name == "a":
    \\        return Some(Cmd(name="a", args=["x"]))
    \\    return None
    \\
    \\func keep(own c: Cmd) -> int:
    \\    return len(c.args)
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "own NAME of a local narrowed to Some moves the payload, and a later read of NAME is a use after the move (NARROW-OWN)" {
    try accepts(std.testing.allocator, narrowed_head ++
        \\func pick(name: str) -> Inv fails str:
        \\    mut found = find(name)
        \\    if found is None:
        \\        fail "unknown"
        \\    return Inv(cmd=own found)
        \\
        \\func count(own found: Cmd?) -> int:
        \\    if found is None:
        \\        return 0
        \\    return keep(own found)
        \\
        \\func again(name: str) -> int:
        \\    mut found = find(name)
        \\    if found is None:
        \\        return 0
        \\    const c = own found
        \\    found = find("b")
        \\    return len(c.args)
        \\
        \\func back(name: str) -> Cmd fails str:
        \\    const found = find(name)
        \\    if found is None:
        \\        fail "unknown"
        \\    return found
    );
    try refuses(std.testing.allocator, narrowed_head ++
        \\func pick(name: str) -> int:
        \\    const found = find(name)
        \\    if found is None:
        \\        return 0
        \\    const n = keep(own found)
        \\    return n + len(found.name)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator, narrowed_head ++
        \\func pick(name: str) -> int:
        \\    const found = find(name)
        \\    if found is None:
        \\        return 0
        \\    mut total = 0
        \\    for i in range(2):
        \\        total += keep(own found)
        \\    return total
    , "E_SINGLE_OWNER_LOOP");
}

test "a bare read of a narrowed owner offers own before the copy, and writes it where nothing reads the owner after (NARROW-OWN)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const repaired = try narrowedRefusal(a, narrowed_head ++
        \\func pick(name: str) -> Inv fails str:
        \\    mut found = find(name)
        \\    if found is None:
        \\        fail "unknown"
        \\    return Inv(cmd=found)
    , "E_SINGLE_OWNER_BORROW", "a bare `found` only lends the local `found`, and field `cmd` of `Inv` would keep it after `found` ends; " ++
        "write `own found` to give it, or `copy(found)` to keep both");
    try std.testing.expect(std.mem.indexOf(u8, repaired.?, "return Inv(cmd=own found)") != null);
    // Read again after the store: the message still names both spellings, and no edit is certain.
    try std.testing.expectEqual(@as(?[]const u8, null), try narrowedRefusal(a, narrowed_head ++
        \\func pick(name: str) -> Inv fails str:
        \\    const found = find(name)
        \\    if found is None:
        \\        fail "unknown"
        \\    const inv = Inv(cmd=found)
        \\    if len(found.name) == 0:
        \\        fail "empty"
        \\    return inv
    , "E_SINGLE_OWNER_BORROW", "write `own found` to give it, or `copy(found)` to keep both"));
}

test "own NAME of a narrowed owner the function does not own names the lender, and its repair writes the copy (NARROW-OWN)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain = try narrowedRefusal(a, narrowed_head ++
        \\func pack(found: Cmd?) -> Inv fails str:
        \\    if found is None:
        \\        fail "none"
        \\    return Inv(cmd=own found)
    , "E_OWN_MARKER", "`own found` cannot give the plain parameter `found`, which only lends it, and field `cmd` of `Inv` would keep " ++
        "it after the call returns; remove `own`, then write `copy(found)` to keep both");
    try std.testing.expect(std.mem.indexOf(u8, plain.?, "return Inv(cmd=copy(found))") != null);
    _ = try narrowedRefusal(a, narrowed_head ++
        \\func pack(mut found: Cmd?) -> Inv fails str:
        \\    if found is None:
        \\        fail "none"
        \\    return Inv(cmd=own found)
    , "E_OWN_MARKER", "`own found` cannot give the `mut` parameter `found`");
    const walked = try narrowedRefusal(a, narrowed_head ++
        \\func total(opts: Cmd?[]) -> int:
        \\    mut sum = 0
        \\    for f in opts:
        \\        if f is None:
        \\            continue
        \\        sum += keep(own f)
        \\    return sum
    , "E_OWN_MARKER", "`f` is lent by the plain parameter `opts`, and the `own` parameter `c` of `keep` needs its own value");
    try std.testing.expect(std.mem.indexOf(u8, walked.?, "keep(copy(f))") != null);
}

/// The declarations the FR75 programs share: a two-field case, a case whose payload is a record, and a writer of two lists.
const fr75_head =
    \\record Bag:
    \\    keys: str[]
    \\    vals: int[]
    \\enum Pairs:
    \\    pairs(keys: str[], vals: int[])
    \\    nothing
    \\enum Slot:
    \\    full(value: Bag)
    \\    empty
    \\func put(mut keys: str[], mut vals: int[]):
    \\    append(mut keys, "k")
    \\    append(mut vals, 1)
    \\func bag(mut b: Bag, mut keys: str[]):
    \\    append(mut b.vals, 1)
    \\    append(mut keys, "k")
    \\func grow(mut vals: int[], keys: str[]):
    \\    append(mut vals, len(keys))
    \\func twice(mut a: int[], mut b: int[]):
    \\    append(mut a, 1)
    \\    append(mut b, 2)
    \\func swap(mut vals: int[], mut t: Pairs):
    \\    append(mut vals, 1)
    \\    t = Pairs.nothing
    \\
;

test "FR75 two payload fields of one match mut arm are disjoint mut arguments, and Core builds the call" {
    try buildsReceiver(std.testing.allocator, fr75_head ++
        \\func add(mut t: Pairs):
        \\    match mut t:
        \\        case pairs(keys, vals):
        \\            put(mut keys, mut vals)
        \\        case nothing:
        \\            pass
        \\func main() -> int:
        \\    mut t = Pairs.pairs(keys=[], vals=[])
        \\    add(mut t)
        \\    mut s = Slot.full(value=Bag(keys=[], vals=[]))
        \\    match mut s:
        \\        case full(value=p):
        \\            put(mut p.keys, mut p.vals)
        \\        case empty:
        \\            pass
        \\    return 0
    );
}

test "FR75 payload bindings stay overlapping inside a list element, twice, beside their place, under a prefix, and read" {
    // The matched place is a list element: fields inside one element are not proven disjoint (ELEM-FIELDS).
    try refusesRule(std.testing.allocator, fr75_head ++
        \\func main() -> int:
        \\    mut ts = [Pairs.pairs(keys=[], vals=[])]
        \\    match mut ts[0]:
        \\        case pairs(keys, vals):
        \\            put(mut keys, mut vals)
        \\        case nothing:
        \\            pass
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
    try refusesRule(std.testing.allocator, fr75_head ++
        \\func main() -> int:
        \\    mut t = Pairs.pairs(keys=[], vals=[])
        \\    match mut t:
        \\        case pairs(keys, vals):
        \\            twice(mut vals, mut vals)
        \\        case nothing:
        \\            pass
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
    try refusesRule(std.testing.allocator, fr75_head ++
        \\func main() -> int:
        \\    mut t = Pairs.pairs(keys=[], vals=[])
        \\    match mut t:
        \\        case pairs(keys, vals):
        \\            swap(mut vals, mut t)
        \\        case nothing:
        \\            pass
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .X2 });
    try refusesRule(std.testing.allocator, fr75_head ++
        \\func main() -> int:
        \\    mut s = Slot.full(value=Bag(keys=[], vals=[]))
        \\    match mut s:
        \\        case full(value=p):
        \\            bag(mut p, mut p.keys)
        \\        case empty:
        \\            pass
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
    // A read beside a `mut` sibling: the build takes the whole payload for the `mut` one, so the read would borrow a taken value.
    try refusesRule(std.testing.allocator, fr75_head ++
        \\func main() -> int:
        \\    mut t = Pairs.pairs(keys=["x"], vals=[])
        \\    match mut t:
        \\        case pairs(keys, vals):
        \\            grow(mut vals, keys)
        \\        case nothing:
        \\            pass
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
}

/// A `match mut` on an enclosing arm's binding, with `CALL` in its inner arm.
const fr75_nested =
    \\enum Inner:
    \\    two(u: int[], v: int[])
    \\    none_in
    \\enum Outer:
    \\    both(x: Inner, y: int[])
    \\    none_out
    \\func fill(mut a: int[], mut b: int[]):
    \\    append(mut a, 1)
    \\    append(mut b, 2)
    \\func grab(mut a: int[], mut b: Inner):
    \\    append(mut a, 1)
    \\func main(out: Stream) -> int:
    \\    mut t = Outer.both(x=Inner.two(u=[], v=[]), y=[])
    \\    match mut t:
    \\        case both(x, y):
    \\            match mut x:
    \\                case two(u, v):
    \\                    CALL
    \\                case none_in:
    \\                    pass
    \\        case none_out:
    \\            pass
    \\    print(out, t)
    \\    return 0
    \\
;

// FR77: Core takes the inner payload under a tag test of its own, so its IR for these calls passes the strict verifier
// (`nested_match_mut_test.zig`), and the bindings name their places as one arm's do.
test "FR75 bindings of a match mut on an enclosing arm's binding, and of two arms, are disjoint in one call and run" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one_arm = try std.mem.replaceOwned(u8, a, fr75_nested, "CALL", "fill(mut u, mut v)");
    try executes(std.testing.allocator, one_arm, "Outer.both(x=Inner.two(u=[1], v=[2]), y=[])\n");
    const two_arms = try std.mem.replaceOwned(u8, a, fr75_nested, "CALL", "fill(mut u, mut y)");
    try executes(std.testing.allocator, two_arms, "Outer.both(x=Inner.two(u=[1], v=[]), y=[2])\n");
    const under_place = try std.mem.replaceOwned(u8, a, fr75_nested, "CALL", "grab(mut u, mut x)");
    try refusesRule(std.testing.allocator, under_place, .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
}

// FR83: a Debug test run once read `0xaaaaaaaaaaaaaaaa` from `BorrowedCollections.literal` (memory written as undefined under a live
// table). `stray` is what the Debug assertion in `markStores` reads: it accepts `none` and every local, and names the first entry that
// is neither. A panic cannot be caught inside a Zig test, so the panic itself is not run here.
test "FR83 BorrowedCollections.stray accepts none and every local and names an entry that names no local" {
    const none = std.math.maxInt(usize);
    var slots = [_]bool{ true, false, true };
    var literal = [_]usize{ none, 2, none };
    var receiver = [_]usize{ 0, none, none };
    var staged = [_]usize{ none, none, 1 };
    var why = [_]unique.BorrowedCollections.Owning{ .{}, .{}, .{} };
    const table: unique.BorrowedCollections = .{ .slots = &slots, .receiver = &receiver, .literal = &literal, .staged = &staged, .why = &why };
    try std.testing.expect(table.stray() == null);
    literal[1] = 0xaaaaaaaaaaaaaaaa;
    const found = table.stray().?;
    try std.testing.expectEqualStrings("literal", found.table);
    try std.testing.expectEqual(@as(usize, 1), found.slot);
    try std.testing.expectEqual(@as(usize, 0xaaaaaaaaaaaaaaaa), found.index);
    literal[1] = none;
    staged[0] = 3;
    try std.testing.expectEqualStrings("staged", table.stray().?.table);
}

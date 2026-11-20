//! R3a, the mixed-return refusal (borrowed-returns plan §2 rule 4): a function
//! whose returns mix a place of a borrowed parameter with a new value is refused
//! once, as `E_BORROW_MIXED`, with a `copy(...)` repair on every borrowed return.
//! `None`, literals and constants are not new values, and a function whose
//! borrowed returns are all copied is accepted.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

/// Helpers every shape needs: `make_list` and `make_text` are new values, and
/// `first_part` is a view of its argument (a borrowing call result).
const helpers =
    \\func make_list() -> str[]:
    \\    mut out: str[] = []
    \\    append(mut out, "x")
    \\    return out
    \\
    \\
    \\func make_text() -> str:
    \\    return "x"
    \\
    \\
    \\func first_part(s: str) -> str from s:
    \\    return s[0:2]
    \\
    \\
;

/// `source` with the entry point a whole-program check needs.
fn withEntry(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ source, "\n\nfunc main() -> int:\n    return 0\n" });
}

/// Check `source`, which must pass, with the ownership contract.
fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, source);
    var failure: unique.Failure = .{};
    try unique.check(a, try support.checkedProgram(a, text), &failure);
}

/// Check `source`, which must be refused with `code`, and whose repairs wrap
/// exactly the `borrowed` texts, in source order. The rendered JSON diagnostic
/// carries one `copy(` and one `)` edit per repaired text.
/// Check that the program is accepted by the ownership checker (R3b: a borrowed return that a `None` accompanies).
fn accepted(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, source);
    var failure: unique.Failure = .{};
    try unique.check(a, try support.checkedProgram(a, text), &failure);
}

fn refusedWith(backing: std.mem.Allocator, source: []const u8, code: []const u8, borrowed: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, source);
    const src = try language.source.Source.init(a, "mixed.selka", text);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, try support.checkedProgram(a, text), src, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (std.mem.eql(u8, code, "E_BORROW_MIXED")) try std.testing.expectEqual(language.ownership_rules.Rule.R5, failure.rule.?);
    const spans = if (failure.copy.span) |span| &[_]language.source.Span{span} else failure.copy.borrowed;
    try std.testing.expectEqual(borrowed.len, spans.len);
    for (borrowed, spans) |want, span| try std.testing.expectEqualStrings(want, text[span.start..span.end]);
    if (failure.repair == .explicit_fix) {
        var removed = false;
        for (failure.repair.explicit_fix) |edit| {
            if (edit.text.len != 0) continue;
            removed = std.mem.indexOf(u8, src.text(edit.span), "from ") != null;
        }
        try std.testing.expect(removed);
    }
    var rendered: std.ArrayList(u8) = .empty;
    try unique.render(a, src, failure, .json, &rendered);
    var opened: usize = 0;
    var rest = rendered.items;
    while (std.mem.indexOf(u8, rest, "\"text\":\"copy(\"")) |at| {
        opened += 1;
        rest = rest[at + 1 ..];
    }
    try std.testing.expectEqual(borrowed.len, opened);
}

/// A mixed refusal for `source` naming `borrowed` as its repairs.
fn mixed(backing: std.mem.Allocator, source: []const u8, borrowed: []const []const u8) !void {
    try refusedWith(backing, source, "E_BORROW_MIXED", borrowed);
}

test "mixed return: a whole parameter on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(xs: str[]) -> str[]:
        \\    if len(xs) > 2:
        \\        return xs
        \\    return make_list()
        \\
    , &.{"xs"});
}

test "mixed return: a field of a parameter on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\record Box:
        \\    words: str[]
        \\
        \\
        \\func pick(box: Box) -> str[]:
        \\    if len(box.words) > 2:
        \\        return box.words
        \\    return make_list()
        \\
    , &.{"box.words"});
}

test "mixed return: an element of a parameter on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(xs: str[]) -> str:
        \\    if len(xs) > 0:
        \\        return xs[0]
        \\    return make_text()
        \\
    , &.{"xs[0]"});
}

test "mixed return: a dictionary value of a parameter on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str) -> str[]:
        \\    if k in d:
        \\        return d[k]
        \\    return make_list()
        \\
    , &.{"d[k]"});
}

test "mixed return: a match payload of a parameter on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\enum Choice:
        \\    words(value: str[])
        \\    empty(value: Unit)
        \\
        \\
        \\func pick(choice: Choice) -> str[]:
        \\    match choice:
        \\        case words(value=items):
        \\            return items
        \\        case empty(value=_):
        \\            return make_list()
        \\
    , &.{"items"});
}

test "mixed return: a slice of a parameter on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(s: str) -> str:
        \\    if len(s) > 2:
        \\        return s[1:3]
        \\    return make_text()
        \\
    , &.{"s[1:3]"});
}

test "mixed return: Some of a place on one path is refused with its copy inside Some" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str) -> str[]?:
        \\    if k in d:
        \\        return Some(d[k])
        \\    return Some(make_list())
        \\
    , &.{"d[k]"});
}

test "mixed return: a fails success of a place on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str) -> str[] fails str:
        \\    if k in d:
        \\        return d[k]
        \\    return make_list()
        \\
    , &.{"d[k]"});
}

test "mixed return: a borrowed const binding returned on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str) -> str[]:
        \\    const found = d[k]
        \\    if len(found) > 1:
        \\        return found
        \\    return make_list()
        \\
    , &.{"found"});
}

test "mixed return: a borrowing call result on one path is refused with its copy" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(s: str) -> str:
        \\    if len(s) > 4:
        \\        return first_part(s)
        \\    return make_text()
        \\
    , &.{"first_part(s)"});
}

test "mixed return: every borrowed return is one refusal with a repair each" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str, j: str) -> str[]:
        \\    if k in d:
        \\        return d[k]
        \\    if j in d:
        \\        return d[j]
        \\    return make_list()
        \\
    , &.{ "d[k]", "d[j]" });
}

test "mixed return: the R0 spike probe that aborted at run time is refused" {
    try mixed(std.testing.allocator,
        // migrate-embedded: skip original mixed-origin return refusal and copy-repair witness
        \\func make_list() -> str[]:
        \\    mut out: str[] = []
        \\    append(mut out, "x")
        \\    return out
        \\
        \\
        \\func pick(table: dict[str, str[]], key: str) -> str[]:
        \\    if key in table:
        \\        return table[key]
        \\    return make_list()
        \\
    , &.{"table[key]"});
}

test "mixed return: a copy on every borrowed return is accepted" {
    try accepts(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str) -> str[]:
        \\    if k in d:
        \\        return copy(d[k])
        \\    return make_list()
        \\
    );
}

test "mixed return: None beside a borrowed Some is not a new value, so the borrow is accepted (R3b)" {
    try accepted(std.testing.allocator,
        \\func pick(d: dict[str, str[]], k: str) -> str[]? from d:
        \\    if k in d:
        \\        return Some(d[k])
        \\    return None
        \\
    );
}

test "mixed return: a text literal beside a declared parameter view is neutral" {
    try accepted(std.testing.allocator,
        \\func line_at(text: str, n: int) -> str from text:
        \\    if n < 0:
        \\        return "none"
        \\    return text[0:n]
        \\
    );
}

test "mixed return: an empty list literal beside a borrowed list is neutral (4e)" {
    try accepted(std.testing.allocator,
        \\record Box:
        \\    words: str[]?
        \\
        \\
        \\func words_of(box: Box) -> str[] from box:
        \\    match box.words:
        \\        case Some(words):
        \\            return words
        \\        case None:
        \\            return []
        \\
        \\
        \\func row_of(rows: int[][], i: int) -> int[]? from rows:
        \\    if i < len(rows):
        \\        return Some(rows[i])
        \\    return Some([])
        \\
    );
}

test "mixed return: a list with elements or a named empty list beside a borrow remains R5 (4e)" {
    try mixed(std.testing.allocator,
        \\func pick(xs: int[], i: int) -> int[] from xs:
        \\    if i > 0:
        \\        return xs
        \\    return [1]
        \\
    , &.{"xs"});
    try mixed(std.testing.allocator,
        \\func pick(xs: int[], i: int) -> int[] from xs:
        \\    if i > 0:
        \\        return xs
        \\    const none: int[] = []
        \\    return none
        \\
    , &.{"xs"});
}

test "mixed return: allocated text beside a declared parameter view remains R5" {
    try mixed(std.testing.allocator,
        // migrate-embedded: skip original mixed-origin return refusal and copy-repair witness
        \\func line_at(text: str, n: int) -> str from text:
        \\    if n < 0:
        \\        return "none" + str(n)
        \\    return text[0:n]
        \\
    , &.{"text[0:n]"});
}

test "mixed return: finishReturns keeps the first refusal when a later statement fails" {
    try refusedWith(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str) -> str[]:
        \\    mut owned = make_list()
        \\    if k in d:
        \\        return d[k]
        \\    const moved = own owned
        \\    append(mut owned, "y")
        \\    return moved
        \\
    , "E_SINGLE_OWNER_MOVED", &.{});
}

test "mixed return: checkStatement defers a borrowed return past a new value that comes first" {
    try mixed(std.testing.allocator, helpers ++
        \\func pick(d: dict[str, str[]], k: str) -> str[]:
        \\    if k not in d:
        \\        return make_list()
        \\    return d[k]
        \\
    , &.{"d[k]"});
}

test "mixed return: a function in an imported module names its two lines as the module's own lines" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();
    var entries = [_]language.embedded_project.File{
        .{ .path = "main.selka", .bytes = "import ev\n\n\nfunc main() -> int:\n    return 0\n" },
        .{ .path = "pad.selka", .bytes = "public func pad1() -> int:\n    return 1\n\n\npublic func pad2() -> int:\n    return 2\n\n\npublic func pad3() -> int:\n    return 3\n" },
        .{ .path = "ev.selka", .bytes = "import pad\n\n\npublic func tip(name: str, count: int) -> str from name:\n    if count == 0:\n        return name\n    return name + \"x\" + str(count + pad.pad1())\n" },
    };
    const Files = struct {
        entries: []language.embedded_project.File,
        fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return language.embedded_project.read(allocator, self.entries, path, limit);
        }
    };
    var files: Files = .{ .entries = &entries };
    var project = language.project.Project.init(aa);
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(aa, compilation.program.?, compilation.src, &failure));
    try std.testing.expectEqualStrings("E_BORROW_MIXED", failure.code);
    try std.testing.expectEqualStrings("`ev::tip` returns a borrow on line 6 and a new value on line 7; write copy(...) around each borrowed return", failure.message);
}

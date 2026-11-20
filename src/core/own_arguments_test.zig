//! Call-site ownership behavior is checked by Core, including each certain fix.
const std = @import("std");
const report = std.debug.print;
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");
const t = std.testing;

fn withEntry(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ text, "\n\nfunc main() -> int:\n    return 0\n" });
}

fn accepted(a: std.mem.Allocator, text: []const u8) !void {
    const unit = try support.checkSource(a, try withEntry(a, text));
    try t.expect(unit.passed);
    var failure: ownership.Failure = .{};
    ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
        reportFailure(unit.src.?, failure, text);
        return err;
    };
}

fn reportFailure(src: language.source.Source, failure: ownership.Failure, text: []const u8) void {
    const location = src.locate(failure.span.start);
    const rule = if (failure.rule) |value| @tagName(value) else "none";
    report("{s}/{s}: {s}\n{s}:{d}:{d}: {s}\nsource:\n{s}\n", .{
        failure.code, rule, failure.message, location.path, location.line, location.column, location.text, text,
    });
}

const Case = struct {
    text: []const u8,
    before: []const u8,
    after: []const u8,
    code: []const u8 = "E_OWN_MARKER",
    message: ?[]const u8 = null,
};

fn editsFromJson(a: std.mem.Allocator, rendered: []const u8) ![]language.diagnostic.Edit {
    const parsed = try std.json.parseFromSlice(std.json.Value, a, rendered, .{});
    const diagnostic = parsed.value.object.get("diagnostic").?.object;
    const fix = diagnostic.get("fix") orelse return error.TestUnexpectedResult;
    const values = fix.object.get("edits").?.array.items;
    const edits = try a.alloc(language.diagnostic.Edit, values.len);
    for (values, edits) |value, *edit| {
        const bytes = value.object.get("bytes").?.object;
        edit.* = .{
            .span = .{ .start = @intCast(bytes.get("start").?.integer), .end = @intCast(bytes.get("end").?.integer) },
            .text = value.object.get("text").?.string,
        };
    }
    std.mem.sort(language.diagnostic.Edit, edits, {}, struct {
        fn before(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start < right.span.start;
        }
    }.before);
    return edits;
}

fn expectFixed(a: std.mem.Allocator, case: Case) !void {
    const text = try withEntry(a, case.text);
    errdefer report("own repair case: {s}\n", .{case.before});
    const unit = try support.checkSource(a, text);
    try t.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try t.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try t.expectEqualStrings(case.code, failure.code);
    if (case.message) |message| try t.expectEqualStrings(message, failure.message);
    try t.expect(failure.rule != null);
    var rendered: std.ArrayList(u8) = .empty;
    try ownership.render(a, unit.src.?, failure, .json, &rendered);
    const edits = try editsFromJson(a, rendered.items);
    var fixed: std.ArrayList(u8) = .empty;
    var offset: usize = 0;
    for (edits) |edit| {
        try t.expect(edit.span.start >= offset);
        try fixed.appendSlice(a, text[offset..edit.span.start]);
        try fixed.appendSlice(a, edit.text);
        offset = edit.span.end;
    }
    try fixed.appendSlice(a, text[offset..]);
    const expected = try std.mem.replaceOwned(u8, a, text, case.before, case.after);
    try t.expectEqualStrings(expected, fixed.items);
    const after = try support.checkSource(a, fixed.items);
    try t.expect(after.passed);
    failure = .{};
    ownership.checkWithSource(a, after.program.?, after.src.?, &failure) catch |err| {
        reportFailure(after.src.?, failure, fixed.items);
        return err;
    };
}

const take_record =
    \\record State:
    \\    keys: int[]
    \\func make(own keys: int[]) -> State:
    \\    return State(keys=own keys)
    \\
;

test "O4 own call markers repair missing fresh scalar and readonly positions" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const cases = [_]Case{
        .{ .text = take_record ++
            \\func use() -> int:
            \\    mut samples = [1, 2]
            \\    const held = make(samples)
            \\    return len(held.keys)
        , .before = "make(samples)", .after = "make(own samples)", .message = "a bare `samples` only lends the local `samples`, and the `own` parameter `keys` of `make` needs its own value; " ++
            "write `own samples` to give it, or `copy(samples)` to keep both" },
        .{ .text = take_record ++
            \\func fresh() -> int[]:
            \\    return [1, 2]
            \\func use() -> int:
            \\    const held = make(own fresh())
            \\    return len(held.keys)
        , .before = "make(own fresh())", .after = "make(fresh())", .message = "a fresh value is already owned, so `own` adds nothing; remove `own`" },
        .{ .text =
        \\func bump(own value: int) -> int:
        \\    return value + 1
        \\func use() -> int:
        \\    mut count = 1
        \\    return bump(own count)
        , .before = "bump(own count)", .after = "bump(count)", .message = "a scalar has no managed storage to transfer; remove own" },
        .{ .text =
        \\func plain(keys: int[]) -> int:
        \\    return len(keys)
        \\func use() -> int:
        \\    mut samples = [1, 2]
        \\    return plain(own samples)
        , .before = "plain(own samples)", .after = "plain(samples)", .message = "`own samples` gives `samples`, but this argument is only read; remove `own`" },
    };
    for (cases) |case| try expectFixed(arena.allocator(), case);
}

test "O4 own parameters may be stored returned mutated and rebound" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try accepted(arena.allocator(), take_record ++
        \\func keep(own keys: int[]) -> int:
        \\    const held = make(own keys)
        \\    return len(held.keys)
        \\func with_item(own keys: str[]) -> str[]:
        \\    append(mut keys, "k")
        \\    return keys
        \\func reset(own keys: str[]) -> str[]:
        \\    keys = ["fresh"]
        \\    return keys
        \\func first_of(own keys: int[]) -> int:
        \\    return keys[0]
        \\func callback_use() -> int:
        \\    const apply: func(own int[]) -> int = first_of
        \\    mut samples = [5, 6]
        \\    return apply(own samples)
        \\func use() -> int:
        \\    mut samples = [1, 2, 3]
        \\    mut seed: str[] = []
        \\    const built = with_item(own seed)
        \\    mut again: str[] = ["old"]
        \\    const fresh = reset(own again)
        \\    return keep(own samples) + len(built) + len(fresh)
    );
}

test "O4 own can give away a field by consuming its owned record carrier" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try accepted(arena.allocator(), take_record ++
        \\func use(own state: State) -> int:
        \\    const held = make(own state.keys)
        \\    return len(held.keys)
    );
    try expectFixed(arena.allocator(), .{
        .text = take_record ++
            \\func use(state: State) -> int:
            \\    const held = make(own state.keys)
            \\    return len(held.keys)
        ,
        .before = "make(own state.keys)",
        .after = "make(copy(state.keys))",
        .code = "E_SINGLE_OWNER_BORROW",
    });
}

test "O4 own append markers preserve fresh values and require named moves" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try accepted(arena.allocator(),
        \\func use() -> int:
        \\    mut rows: int[][] = []
        \\    mut inner = [1]
        \\    append(mut rows, own inner)
        \\    append(mut rows, [2])
        \\    return len(rows)
    );
    const cases = [_]Case{
        .{ .text =
        \\func fresh() -> int[]:
        \\    return [2]
        \\func use() -> int:
        \\    mut rows: int[][] = []
        \\    append(mut rows, own fresh())
        \\    return len(rows)
        , .before = "own fresh()", .after = "fresh()" },
        .{
            .text =
            // A returned list owns its elements; one that only lends them borrows `piece` instead (RB2).
            \\func use() -> str[]:
            \\    mut rows: str[] = []
            \\    const piece = "ab" + "cd"
            \\    append(mut rows, piece)
            \\    return rows
            ,
            .before = "append(mut rows, piece)",
            .after = "append(mut rows, own piece)",
        },
        .{ .text =
        \\func fill(own s: str, mut rows: str[]):
        \\    append(mut rows, s)
        , .before = "append(mut rows, s)", .after = "append(mut rows, own s)" },
    };
    for (cases) |case| try expectFixed(arena.allocator(), case);
}

test "O4 own borrowed parameters require an independent copy" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try expectFixed(arena.allocator(), .{
        .text =
        \\func fill(s: str, mut rows: str[]):
        \\    append(mut rows, own s)
        ,
        .before = "own s)",
        .after = "copy(s))",
        .code = "E_SINGLE_OWNER_BORROW",
    });
    try expectFixed(arena.allocator(), .{
        .text =
        \\func my_take(own s: str) -> int:
        \\    return len(s)
        \\func keep() -> int:
        \\    const s = "ab" + "cd"
        \\    return my_take(s)
        ,
        .before = "my_take(s)",
        .after = "my_take(own s)",
    });
}

test "O4 own library storage parameters retain marker fixes (sets.add; dicts.add borrows its key)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const cases = [_]Case{
        .{ .text =
        \\import sets
        \\func use() -> int:
        \\    mut seen: set[str] = set()
        \\    const word = "ab" + "cd"
        \\    sets.add(mut seen, word)
        \\    return len(seen)
        , .before = "sets.add(mut seen, word)", .after = "sets.add(mut seen, own word)" },
    };
    for (cases) |case| try expectFixed(arena.allocator(), case);
}

const implicit_some_header =
    \\func size(value: bytes?) -> int:
    \\    if value is None:
    \\        return 0
    \\    mut text = copy(value)
    \\    return len(text)
    \\func deep(value: bytes??) -> int:
    \\    if value is None:
    \\        return 0
    \\    return 1
    \\func fresh() -> bytes:
    \\    return b"fresh"
    \\record Box:
    \\    data: bytes
    \\
;

fn refusedWith(a: std.mem.Allocator, text: []const u8, code: []const u8) !ownership.Failure {
    const unit = try support.checkSource(a, try withEntry(a, text));
    try t.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try t.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try t.expectEqualStrings(code, failure.code);
    return failure;
}

test "O4 implicit Some moves the named value the same way an explicit Some does" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try accepted(arena.allocator(), implicit_some_header ++
        \\func const_binding() -> int:
        \\    const label = b"brand"
        \\    return size(own label)
        \\func mut_binding() -> int:
        \\    mut label = b"brand"
        \\    return size(own label)
        \\func nested() -> int:
        \\    mut label = b"brand"
        \\    return deep(own label)
        \\func field() -> int:
        \\    mut box = Box(data=b"brand")
        \\    return size(own box.data)
        \\func explicit() -> int:
        \\    mut label = b"brand"
        \\    return size(Some(own label))
        \\func already_optional() -> int:
        \\    mut maybe: bytes? = Some(b"brand")
        \\    return deep(own maybe)
    );
}

test "O4 implicit Some keeps the bare move refusal and its own repair" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const cases = [_]Case{
        .{ .text = implicit_some_header ++
            \\func use() -> int:
            \\    mut label = b"brand"
            \\    return size(label)
        , .before = "size(label)", .after = "size(own label)", .message = "a bare `label` only lends the local `label`, and the argument of the call needs its own value; write `own label` to give it, or `copy(label)` to keep both" },
        .{ .text = implicit_some_header ++
            \\func use() -> int:
            \\    mut label = b"brand"
            \\    return deep(label)
        , .before = "deep(label)", .after = "deep(own label)", .message = "a bare `label` only lends the local `label`, and the argument of the call needs its own value; write `own label` to give it, or `copy(label)` to keep both" },
        .{ .text = implicit_some_header ++
            \\func use() -> int:
            \\    return size(own fresh())
        , .before = "size(own fresh())", .after = "size(fresh())", .message = "a fresh value is already owned, so `own` adds nothing; remove `own`" },
    };
    for (cases) |case| try expectFixed(arena.allocator(), case);
}

test "O4 implicit Some hands the value over so later reads are refused and explicit own Some stays refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const moved = try refusedWith(a, implicit_some_header ++
        \\func use() -> int:
        \\    mut label = b"brand"
        \\    const n = size(own label)
        \\    return n + len(label)
    , "E_SINGLE_OWNER_MOVED");
    try t.expectEqual(language.ownership_rules.Rule.B3, moved.rule.?);
    const explicit = try refusedWith(a, implicit_some_header ++
        \\func use() -> int:
        \\    mut label = b"brand"
        \\    return size(own Some(label))
    , "E_OWN_MARKER");
    try t.expectEqualStrings("a fresh value is already owned, so `own` adds nothing; remove `own`", explicit.message);
    try t.expectEqual(language.ownership_rules.Rule.B2, explicit.rule.?);
}

test "O4 own survives intrinsic folding staging and unused expressions with certain removal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const cases = [_]Case{
        .{ .text =
        \\func use() -> int:
        \\    const text = "x"
        \\    return ord(own text)
        , .before = "own text", .after = "text" },
        .{ .text =
        \\func use() -> bool:
        \\    const octets = b"abc"
        \\    return 0 in own octets
        , .before = "own octets", .after = "octets" },
        .{ .text =
        \\func use() -> int:
        \\    const stride = 1
        \\    const values = list(range(0, 3, own stride))
        \\    return len(values)
        , .before = "own stride", .after = "stride" },
        .{ .text =
        \\func use() -> int:
        \\    const stride = 1
        \\    const values = list(range(0, 3, -(own stride)))
        \\    return len(values)
        , .before = "own stride", .after = "stride" },
        .{ .text =
        \\func use() -> int:
        \\    const values = [1]
        \\    return len(own values)
        , .before = "own values", .after = "values" },
        .{ .text =
        \\func use() -> int:
        \\    const values = [1]
        \\    const kept = copy(own values)
        \\    return len(kept)
        , .before = "own values", .after = "values" },
        .{ .text =
        \\import strings
        \\func use() -> int:
        \\    const text = "abc"
        \\    return strings.char_count(own text)
        , .before = "own text", .after = "text" },
        .{ .text =
        \\func use() -> int:
        \\    const count = 3
        \\    return int(own count)
        , .before = "own count", .after = "count" },
        .{ .text =
        \\func use() -> float:
        \\    const count = 3.0
        \\    return float(own count)
        , .before = "own count", .after = "count" },
        .{ .text =
        \\func use() -> int:
        \\    const count = 1
        \\    const unused = own count
        \\    return 0
        , .before = "own count", .after = "count" },
        .{ .text =
        \\func use() -> bool:
        \\    const truth = True
        \\    return False and (own truth)
        , .before = "own truth", .after = "truth" },
        .{ .text =
        \\func use() -> int:
        \\    const count = 3
        \\    return 1 + (own count)
        , .before = "own count", .after = "count" },
        .{ .text =
        \\func use() -> int:
        \\    const value = 1
        \\    match own value:
        \\        case 1:
        \\            return 42
        \\        case _:
        \\            return 0
        , .before = "own value", .after = "value" },
        .{ .text =
        \\import dicts
        \\func use() -> int:
        \\    const mapping = {"key": 1}
        \\    return len(own dicts.keys(mapping))
        , .before = "own dicts.keys(mapping)", .after = "dicts.keys(mapping)" },
        .{ .text =
        \\import dicts
        \\func use() -> int:
        \\    const mapping = {"key": 1}
        \\    const keys = list(own dicts.keys(mapping))
        \\    return len(keys)
        , .before = "own dicts.keys(mapping)", .after = "dicts.keys(mapping)" },
    };
    for (cases) |case| try expectFixed(arena.allocator(), case);
}

/// Hash source structure, resolving node-table references and omitting only own
/// wrapper nodes and location metadata. Equal values mean equal parse trees.
const FxParseShape = struct {
    syntax: language.ast.Program,
    src: language.source.Source,
    hash: std.crypto.hash.sha2.Sha256 = .init(.{}),

    fn add(self: *FxParseShape, comptime T: type, value: T) void {
        if (T == language.ast.NodeId) {
            const node = self.syntax.nodes.items[@backingInt(value)];
            if (node.data == .own_argument) return self.add(language.ast.NodeId, node.data.own_argument);
            return self.add(@TypeOf(node.data), node.data);
        }
        if (T == language.ast.StatementId) {
            const node = self.syntax.statements.items[@backingInt(value)];
            return self.add(@TypeOf(node.data), node.data);
        }
        if (T == language.source.Span) {
            const bytes = self.src.text(value);
            self.hash.update(bytes);
            self.hash.update("\x00");
            return;
        }
        switch (@typeInfo(T)) {
            .@"struct" => |info| inline for (info.field_names, info.field_types) |name, Field| {
                if (comptime !std.mem.eql(u8, name, "span")) self.add(Field, @field(value, name));
            },
            .@"union" => |info| {
                const tag = std.meta.activeTag(value);
                self.hash.update(@tagName(tag));
                inline for (info.field_names, info.field_types) |name, Field| {
                    if (tag == @field(info.tag_type.?, name)) self.add(Field, @field(value, name));
                }
            },
            .pointer => |info| {
                const count = value.len;
                self.hash.update(std.mem.asBytes(&count));
                for (value) |item| self.add(info.child, item);
            },
            .optional => |info| {
                self.hash.update(if (value != null) "some" else "none");
                if (value) |item| self.add(info.child, item);
            },
            .@"enum" => self.hash.update(@tagName(value)),
            .bool => self.hash.update(if (value) "true" else "false"),
            .int => self.hash.update(std.mem.asBytes(&value)),
            .void => {},
            else => @compileError("extend the source parse-shape test for " ++ @typeName(T)),
        }
    }
};

fn fxParseShape(a: std.mem.Allocator, bytes: []const u8) ![32]u8 {
    var c = try language.Compilation.init(a, "shape.selka", bytes);
    defer c.deinit();
    try c.parse();
    var shape: FxParseShape = .{ .syntax = c.syntax.?, .src = c.src };
    shape.add(@TypeOf(c.syntax.?.functions), c.syntax.?.functions);
    shape.add(@TypeOf(c.syntax.?.types), c.syntax.?.types);
    shape.add(@TypeOf(c.syntax.?.lambdas), c.syntax.?.lambdas);
    shape.add(@TypeOf(c.syntax.?.attributes), c.syntax.?.attributes);
    shape.add(@TypeOf(c.syntax.?.docstrings), c.syntax.?.docstrings);
    return shape.hash.finalResult();
}

fn fxRemovalShapes(a: std.mem.Allocator, original: []const u8) !usize {
    var current = original;
    var removed: usize = 0;
    while (removed < 50) {
        const unit = try support.checkSource(a, current);
        try t.expect(unit.passed);
        var failure: ownership.Failure = .{};
        ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
            try t.expectEqual(error.Rejected, err);
            try t.expectEqualStrings("E_OWN_MARKER", failure.code);
            var rendered: std.ArrayList(u8) = .empty;
            try ownership.render(a, unit.src.?, failure, .json, &rendered);
            const edits = try editsFromJson(a, rendered.items);
            try t.expectEqual(@as(usize, 1), edits.len);
            try t.expectEqualStrings("", edits[0].text);
            const removed_prefix = std.mem.trim(u8, current[edits[0].span.start..edits[0].span.end], " \t");
            try t.expectEqualStrings("own", removed_prefix);
            const next = try std.mem.concat(a, u8, &.{ current[0..edits[0].span.start], current[edits[0].span.end..] });
            try t.expectEqual(try fxParseShape(a, current), try fxParseShape(a, next));
            current = next;
            removed += 1;
            continue;
        };
        return removed;
    }
    return error.TestUnexpectedResult;
}

test "F2 every certain own removal in the migration corpus preserves the remaining parse tree" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(t.io, "test/fixtures/fix-migration/owned_moves/redundant.selka", a, .limited(1 << 20));
    try t.expectEqual(@as(usize, 5), try fxRemovalShapes(a, text));
}

test "F5 fail own removal in the migration corpus preserves the remaining parse tree" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(t.io, "test/fixtures/fix-migration/fail-name.selka", a, .limited(1 << 20));
    try t.expectEqual(@as(usize, 1), try fxRemovalShapes(a, text));
}

test "two fields of one ordinary record pass as separate mut arguments, and one field twice does not" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const header =
        \\record Lists:
        \\    left: int[]
        \\    right: int[]
        \\func grow(mut a: int[], mut b: int[]):
        \\    append(mut a, 1)
        \\    append(mut b, 2)
        \\
    ;
    try accepted(arena.allocator(), header ++
        \\func apart() -> int:
        \\    mut lists = Lists(left=[], right=[])
        \\    grow(mut lists.left, mut lists.right)
        \\    return len(lists.left) + len(lists.right)
    );
    const failure = try refusedWith(arena.allocator(), header ++
        \\func twice() -> int:
        \\    mut lists = Lists(left=[], right=[])
        \\    grow(mut lists.left, mut lists.left)
        \\    return len(lists.left)
    , "E_SINGLE_OWNER_OVERLAP");
    try t.expect(failure.span.end > failure.span.start);
}

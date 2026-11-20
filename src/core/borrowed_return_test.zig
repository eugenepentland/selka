//! Borrowed results (borrowed returns R3b and R4): a function returns a borrow of its parameters, a caller reads it
//! in place or binds it with `const`, and every other use is refused with its copy repair. The accepted shapes run
//! in tests/lang/borrowed_results.selka; these tests pin the refusals and the checker's shapes.
const std = @import("std");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const language = @import("selka");

test "O3 borrowed signatures recognize only standard optional wrapper identities" {
    const ty: language.typed.Type = @fromBackingInt(language.typed.Type.record_base);
    const nowhere: language.source.Span = .{ .start = 0, .end = 0 };
    var records = [_]language.typed.Record{.{
        .id = ty,
        .name = "OptionFoo",
        .declaration = nowhere,
        .fields = &.{},
        .shape = .{ .variants = .{ .fallible = false, .is_union = true, .cases = &.{
            .{ .name = "none", .declaration = nowhere, .payload = null },
            .{ .name = "some", .declaration = nowhere, .payload = .i64 },
        } } },
    }};
    try std.testing.expect(language.return_borrow.step(&records, ty) == null);
    records[0].name = "Option<i64>";
    try std.testing.expectEqual(language.return_borrow.Step{ .payload = .i64, .tag = 1 }, language.return_borrow.step(&records, ty).?);
    records[0].name = "std_result::Option<i64>";
    try std.testing.expectEqual(language.return_borrow.Step{ .payload = .i64, .tag = 1 }, language.return_borrow.step(&records, ty).?);
    records[0].name = "Outcome";
    records[0].shape.variants = .{ .fallible = true, .is_union = true, .cases = &.{
        .{ .name = "ok", .declaration = nowhere, .payload = .i64 },
        .{ .name = "err", .declaration = nowhere, .payload = .i64 },
    } };
    try std.testing.expect(language.return_borrow.step(&records, ty) == null);
    records[0].name = "Counter";
    records[0].managed = true;
    records[0].shape = .{};
    try std.testing.expect(language.return_borrow.managed(&records, ty));
    try std.testing.expectEqual(language.return_borrow.Kind.value, language.return_borrow.shape(&records, .{ .return_type = ty, .return_origin = .{ .params = &.{0} } }).kind);
}

fn expectFixed(backing: std.mem.Allocator, text: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    const rule: language.ownership_rules.Rule = if (std.mem.eql(u8, code, "E_BORROW_MIXED")) .R5 else .R4;
    try std.testing.expectEqual(rule, failure.rule.?);
    try std.testing.expect(failure.repair == .explicit_fix);
    const edits = try a.dupe(language.diagnostic.Edit, failure.repair.explicit_fix);
    std.mem.sort(language.diagnostic.Edit, edits, {}, struct {
        fn before(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start < right.span.start;
        }
    }.before);
    var rewritten: std.ArrayList(u8) = .empty;
    var cursor: usize = 0;
    for (edits) |edit| {
        try std.testing.expect(edit.span.start >= cursor);
        try rewritten.appendSlice(a, text[cursor..edit.span.start]);
        try rewritten.appendSlice(a, edit.text);
        cursor = edit.span.end;
    }
    try rewritten.appendSlice(a, text[cursor..]);
    try std.testing.expect(std.mem.indexOf(u8, rewritten.items, fragment) != null);
    const after = try support.checkSource(a, rewritten.items);
    try std.testing.expect(after.passed);
    failure = .{};
    try contract.checkWithSource(a, after.program.?, after.src.?, &failure);
}

test "O3 borrowed signatures collect all missing sources in one certain declaration repair" {
    try expectFixed(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func view(data: bytes) -> bytes:
        \\    return data[1:3]
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_UNDECLARED", "-> bytes from data:");
    try expectFixed(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\record Box:
        \\    items: int[]
        \\func choose(left: Box, mut middle: Box, right: Box, which: int) -> int[]:
        \\    if which == 0:
        \\        return left.items
        \\    if which == 1:
        \\        return middle.items
        \\    return right.items
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_UNDECLARED", "-> int[] from left, middle, right:");
    try expectFixed(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func choose(left: int[], right: int[], flag: bool) -> int[] from right:
        \\    if flag:
        \\        return left
        \\    return right
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_UNDECLARED", "-> int[] from left, right:");
}

test "O3 borrowed signatures mixed repair copies returns and removes the declared clause" {
    try expectFixed(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func choose(items: int[], flag: bool) -> int[] from items:
        \\    if flag:
        \\        return items
        \\    return [7]
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_MIXED", "-> int[]:");
}

test "O3 borrowed signatures support text bytes list slices and neutral wrapped alternatives" {
    try expectAccepted(std.testing.allocator,
        \\func text_part(value: str) -> str from value:
        \\    return value[0:1]
        \\func byte_part(value: bytes) -> bytes from value:
        \\    return value[0:1]
        \\func list_part(value: int[]) -> int[] from value:
        \\    return value[0:1]
        \\func checked(value: str, flag: bool) -> str? from value fails str:
        \\    if not flag:
        \\        fail "no value"
        \\    if len(value) == 0:
        \\        return None
        \\    return Some(value[0:1])
        \\func main() -> int:
        \\    return 0
    );
}

test "O3 borrowed signatures preserve const dictionary accessor results and all owner loans" {
    try expectAccepted(std.testing.allocator,
        \\import dicts
        \\func main() -> int:
        \\    mut mapping = {"present": [1]}
        \\    mut fallback = [2]
        \\    const absent = dicts.get(mapping, "missing", fallback)
        \\    const present = dicts.get(mapping, "present", fallback)
        \\    const total = absent[0] + present[0]
        \\    append(mut fallback, 3)
        \\    const inserted = dicts.setdefault(mut mapping, "added", copy(fallback))
        \\    append(mut fallback, 4)
        \\    return total + inserted[0]
    );
    const changes = [_][]const u8{
        "    mapping[\"present\"] = [3]\n",
        "    append(mut fallback, 3)\n",
    };
    for (changes) |change| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const text = try std.mem.concat(arena.allocator(), u8, &.{
            "import dicts\nfunc main() -> int:\n    mut mapping = {\"present\": [1]}\n    mut fallback = [2]\n    const selected = dicts.get(mapping, \"missing\", fallback)\n",
            change,
            "    return selected[0]\n",
        });
        const unit = try support.checkSource(arena.allocator(), text);
        try std.testing.expect(unit.passed);
        var failure: contract.Failure = .{};
        try std.testing.expectError(error.Rejected, contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure));
        try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
        try std.testing.expectEqual(language.ownership_rules.Rule.R2, failure.rule.?);
    }
    try expectRefusal(std.testing.allocator,
        \\import dicts
        \\func main() -> int:
        \\    const mapping = {"present": [1]}
        \\    const fallback = [2]
        \\    mut selected = dicts.get(mapping, "missing", fallback)
        \\    selected = copy(selected)
        \\    return selected[0]
    , "E_SINGLE_OWNER_BORROW");
}

test "O3 borrowed signatures retain readonly text trim receiver provenance" {
    try expectAccepted(std.testing.allocator,
        \\import strings
        \\func left(value: str) -> str from value:
        \\    return strings.lstrip(value)
        \\func right(value: str) -> str from value:
        \\    return strings.rstrip(value)
        \\func both(value: str) -> str from value:
        \\    const trimmed = strings.strip(value)
        \\    return trimmed
        \\func main() -> int:
        \\    return len(left(" left")) + len(right("right ")) + len(both(" both "))
    );
    try expectFixed(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\import strings
        \\func trim(value: str) -> str:
        \\    return strings.strip(value)
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_UNDECLARED", "-> str from value:");
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\import bytes
        \\func trim(value: bytes) -> bytes from value:
        \\    return bytes.strip(value)
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_MIXED");
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\import strings
        \\func trim(value: str) -> str from value:
        \\    return strings.strip_chars(value, " ")
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_MIXED");
}

test "O3 borrowed signatures preserve whole user-named results as ordinary borrowed values" {
    try expectAccepted(std.testing.allocator,
        \\result Outcome:
        \\    ok: str,
        \\    err: str
        \\func forward(value: Outcome) -> Outcome from value:
        \\    return value
        \\func main() -> int:
        \\    return 0
    );
}

test "O3 borrowed signatures scalar generic instances ignore their preserved declaration" {
    try expectFixed(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func identity[T](value: T) -> T:
        \\    return value
        \\func main() -> int:
        \\    const values = [1]
        \\    return identity[int](3) + len(identity[int[]](values))
    , "E_BORROW_UNDECLARED", "-> T from value:");
}

test "O3 borrowed signatures validate source declarations before unused generic bodies and caches" {
    const invalid = [_][]const u8{
        "func unused[T](own value: T) -> T from value:\n    return value\n",
        "func unused[T](value: T) -> T from missing:\n    return value\n",
        "func unused[T](value: T, scalar: int) -> T from scalar:\n    return value\n",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (invalid) |declaration| {
        const text = try std.mem.concat(a, u8, &.{ declaration, "func main() -> int:\n    return 0\n" });
        const unit = try support.checkSource(a, text);
        try std.testing.expect(!unit.passed);
        try std.testing.expectEqualStrings("E_BORROW_SOURCE", unit.diagnostics[0].code);
        try std.testing.expectEqual(language.ownership_rules.Rule.R4, unit.diagnostics[0].provenance.rule.?);
    }
}

test "F6 borrowed signatures refuse and repair repeated eligible source names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func same(value: int[]) -> int[] from value, value:
        \\    return value
        \\func main() -> int:
        \\    return 0
    ;
    const refused = try support.checkSource(a, source);
    try std.testing.expect(!refused.passed);
    try std.testing.expectEqual(@as(usize, 1), refused.diagnostics.len);
    const diagnostic = refused.diagnostics[0];
    try std.testing.expectEqualStrings("E_BORROW_SOURCE", diagnostic.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R4, diagnostic.provenance.rule.?);
    const fix = diagnostic.provenance.fix.?;
    try std.testing.expectEqual(@as(usize, 1), fix.count());
    try std.testing.expectEqualStrings(", value", source[fix.edit.span.start..fix.edit.span.end]);
    try std.testing.expectEqualStrings("", fix.edit.text);
    const fixed = try std.mem.concat(a, u8, &.{ source[0..fix.edit.span.start], fix.edit.text, source[fix.edit.span.end..] });
    const unit = try support.checkSource(a, fixed);
    try std.testing.expect(unit.passed);
    var same: ?language.typed.Function = null;
    for (unit.program.?.functions) |function| {
        if (std.mem.eql(u8, function.name, "same")) same = function;
    }
    try std.testing.expect(same != null);
    try std.testing.expectEqualSlices(u16, &.{0}, language.return_borrow.sources(same.?.signature));
    var failure: contract.Failure = .{};
    try contract.checkWithSource(a, unit.program.?, unit.src.?, &failure);
}

test "O3 borrowed signatures preserve P3 unique origins and P4 scoped file returns" {
    const cases = [_]struct { text: []const u8, code: []const u8, rule: language.ownership_rules.Rule }{
        .{
            .text =
            \\func wrong(mut first: File, mut second: File) -> File from first:
            \\    return first
            \\func main() -> int:
            \\    return 0
            ,
            .code = "E_RESOURCE_ORIGIN",
            .rule = .P3,
        },
        .{
            .text =
            \\func keep(fs: Filesystem, marker: int[]) -> File from marker:
            \\    with fs.open("note", "rb") as file:
            \\        return file
            \\func main() -> int:
            \\    return 0
            ,
            .code = "E_WITH_RESOURCE",
            .rule = .P4,
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (cases) |case| {
        const unit = try support.checkSource(a, case.text);
        try std.testing.expect(unit.passed);
        var failure: contract.Failure = .{};
        try std.testing.expectError(error.Rejected, contract.checkWithSource(a, unit.program.?, unit.src.?, &failure));
        try std.testing.expectEqualStrings(case.code, failure.code);
        try std.testing.expectEqual(case.rule, failure.rule.?);
    }
    try expectAccepted(a,
        \\func lend(mut file: File) -> File from file:
        \\    return file
        \\func main() -> int:
        \\    return 0
    );
}

test "O3 borrowed signatures allow a wrapped view result as a read-only argument" {
    try expectAccepted(std.testing.allocator,
        \\func portion(value: str) -> str? from value:
        \\    return Some(value[0:1])
        \\func count(value: str?) -> int:
        \\    match value:
        \\        case Some(text):
        \\            return len(text)
        \\        case None:
        \\            return 0
        \\func main() -> int:
        \\    const text = "hello"
        \\    const part = portion(text)
        \\    return count(part)
    );
}

fn manyOwners(a: std.mem.Allocator, mutate_last: bool) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    const w = &out.writer;
    try w.writeAll("record Box:\n    items: int[]\nfunc choose(");
    for (0..70) |index| {
        if (index != 0) try w.writeAll(", ");
        try w.print("p{d}: Box", .{index});
    }
    try w.writeAll(", which: int) -> int[] from ");
    for (0..70) |index| {
        if (index != 0) try w.writeAll(", ");
        try w.print("p{d}", .{index});
    }
    try w.writeAll(":\n");
    for (0..69) |index| try w.print("    if which == {d}:\n        return p{d}.items\n", .{ index, index });
    try w.writeAll("    return p69.items\nfunc main() -> int:\n");
    for (0..70) |index| try w.print("    mut owner{d} = Box(items=[{d}])\n", .{ index, index });
    try w.writeAll("    const got = choose(");
    for (0..70) |index| {
        if (index != 0) try w.writeAll(", ");
        try w.print("owner{d}", .{index});
    }
    try w.writeAll(", 0)\n");
    if (mutate_last) try w.writeAll("    owner69.items = [7]\n");
    try w.writeAll("    return len(got)\n");
    return out.toOwnedSlice();
}

test "O3 borrowed signatures keep every owner beyond masks and prototype root budgets alive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectAccepted(arena.allocator(), try manyOwners(arena.allocator(), false));
    try expectRefusal(arena.allocator(), try manyOwners(arena.allocator(), true), "E_SINGLE_OWNER_OVERLAP");
}

/// Check `text` and require that it is refused with `code` by the ownership checker (or by sema).
fn expectRefusal(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    if (!unit.passed) return std.testing.expectEqualStrings(code, unit.diagnostics[0].code);
    var failure: contract.Failure = .{};
    const checked = contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure);
    if (checked) |_| return std.testing.expectEqualStrings(code, "accepted") else |err| {
        try std.testing.expectEqual(error.Rejected, err);
        return std.testing.expectEqualStrings(code, failure.code);
    }
}

/// Check `text` and require that sema and the ownership checker accept it.
fn expectAccepted(allocator: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure);
}

test "R3b: a dictionary value, a list element and an option of one are returned as borrows" {
    try expectAccepted(std.testing.allocator,
        \\func first_items(table: dict[str, str[]], key: str) -> str[] from table:
        \\    return table[key]
        \\func maybe_items(table: dict[str, str[]], key: str) -> str[]? from table:
        \\    if key in table:
        \\        return Some(table[key])
        \\    return None
        \\func element(rows: str[][], i: int) -> str[] from rows:
        \\    return rows[i]
        \\func main(out: Stream) -> int:
        \\    mut table: dict[str, str[]] = {"a": ["x", "y"]}
        \\    print(out, len(first_items(table, "a")))
        \\    return 0
    );
}

test "R3b: a call result bound with const is read, and its owner cannot change while it is live" {
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func first_items(table: dict[str, str[]], key: str) -> str[] from table:
        \\    return table[key]
        \\func main(out: Stream) -> int:
        \\    mut table: dict[str, str[]] = {"a": ["x", "y"]}
        \\    const got = first_items(table, "a")
        \\    table = {"b": ["z"]}
        \\    print(out, len(got))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

test "R3b: a call result bound with mut is refused as a store, with its copy repair" {
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func first_items(table: dict[str, str[]], key: str) -> str[] from table:
        \\    return table[key]
        \\func main(out: Stream) -> int:
        \\    mut table: dict[str, str[]] = {"a": ["x", "y"]}
        \\    mut kept = first_items(table, "a")
        \\    kept = copy(kept)
        \\    print(out, len(kept))
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

test "R3b: a return that is a new value on one path and a borrow on another is E_BORROW_MIXED" {
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func make_list() -> str[]:
        \\    mut out: str[] = []
        \\    append(mut out, "x")
        \\    return out
        \\func pick(table: dict[str, str[]], key: str) -> str[]:
        \\    if key in table:
        \\        return table[key]
        \\    return make_list()
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_MIXED");
}

test "R3b: a borrow of a local cannot be returned" {
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func first_items(table: dict[str, str[]], key: str) -> str[] from table:
        \\    return table[key]
        \\func pick(key: str) -> str[]:
        \\    mut local: dict[str, str[]] = {"a": ["x"]}
        \\    return first_items(local, key)
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

test "R4: a returned borrow is a read, so its owner is not moved into the return" {
    try expectAccepted(std.testing.allocator,
        \\record Node:
        \\    label: str
        \\func label_of(node: Node) -> str from node:
        \\    return node.label
        \\func onward(node: Node) -> str from node:
        \\    const got = label_of(node)
        \\    return got
        \\func main(out: Stream) -> int:
        \\    const node = Node(label="x")
        \\    print(out, len(onward(node)))
        \\    return 0
    );
}

test "O3 borrowed results return a whole text parameter as a declared view" {
    try expectAccepted(std.testing.allocator,
        \\func pick(fallback: str) -> str from fallback:
        \\    return fallback
        \\func main() -> int:
        \\    return 0
    );
}

test "G4: a change of the tree while the label borrowed from it is live is refused (E_SINGLE_OWNER_OVERLAP)" {
    try expectRefusal(std.testing.allocator,
        \\record Node:
        \\    label: str
        \\func label_of(node: Node) -> str from node:
        \\    return node.label
        \\func main() -> int:
        \\    mut tree = Node(label="a")
        \\    const label = label_of(tree)
        \\    tree.label = "x"
        \\    return len(label)
    , "E_SINGLE_OWNER_OVERLAP");
}

test "D10: borrowed call results from the same owner join and retain their source lifetime" {
    try expectAccepted(std.testing.allocator,
        \\func first_items(table: dict[str, str[]], key: str) -> str[] from table:
        \\    return table[key]
        \\func main() -> int:
        \\    mut table: dict[str, str[]] = {"a": ["x", "y"]}
        \\    const ok = True
        \\    const got: str[]
        \\    if ok:
        \\        got = first_items(table, "a")
        \\    else:
        \\        got = first_items(table, "a")
        \\    return len(got)
    );
    // A common declared source makes the joined view definite; it still
    // becomes invalid when that source is replaced before the view is read.
    try expectRefusal(std.testing.allocator,
        \\func first_items(table: dict[str, str[]], key: str) -> str[] from table:
        \\    return table[key]
        \\func main() -> int:
        \\    mut table: dict[str, str[]] = {"a": ["x", "y"]}
        \\    const ok = True
        \\    const got: str[]
        \\    if ok:
        \\        got = first_items(table, "a")
        \\    else:
        \\        got = first_items(table, "a")
        \\    table = {"b": ["z"]}
        \\    return len(got)
    , "E_SLICE_ESCAPES");
}

test "R3b: a scalar field returned beside a new value is not a mixed return, as before" {
    try expectAccepted(std.testing.allocator,
        \\record Node:
        \\    number: int
        \\func total(node: Node, extra: int) -> int:
        \\    if extra > 0:
        \\        return node.number
        \\    return extra + 1
        \\func main() -> int:
        \\    return total(Node(number=2), 0)
    );
}

test "R3b: returnValue refuses a mixed return of a place and a new value (E_BORROW_MIXED, error.Rejected ends the path)" {
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed-return declaration, lifetime or mixed-origin refusal and repair witness
        \\func pick(table: dict[str, str[]], key: str) -> str[]:
        \\    if key in table:
        \\        return table[key]
        \\    return ["new"]
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_MIXED");
}

/// Records whose fields are bytes, and a block of them (lane SK).
const lent_bytes = "record Inst:\n    ref_des: bytes\n    value: bytes\nrecord Block:\n    instances: Inst[]\n";
/// Records whose fields are text, and a block of them (lane SK).
const lent_text = "record Inst:\n    ref_des: str\n    value: str\nrecord Block:\n    instances: Inst[]\n";

test "SK a record lent from its block beside a plain bytes or text source is accepted: the view source lends nothing" {
    try expectAccepted(std.testing.allocator, lent_bytes ++
        \\func instance_of(block: Block, ref_des: bytes) -> Inst? from block, ref_des:
        \\    for inst in block.instances:
        \\        if inst.ref_des == ref_des:
        \\            return Some(inst)
        \\    return None
        \\func main() -> int:
        \\    return 0
    );
    try expectAccepted(std.testing.allocator, lent_text ++
        \\func instance_of(block: Block, ref_des: str) -> Inst? from block, ref_des:
        \\    for inst in block.instances:
        \\        if inst.ref_des == ref_des:
        \\            return Some(inst)
        \\    return None
        \\func main() -> int:
        \\    return 0
    );
}

/// Check `text` and require the ownership checker to refuse it as new storage returned under `from`: a borrow stored into a
/// new value (`E_SINGLE_OWNER_BORROW`) or a mixed return (`E_BORROW_MIXED`).
fn expectNewStorageRefused(allocator: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure));
    const known = std.mem.eql(u8, failure.code, "E_SINGLE_OWNER_BORROW") or std.mem.eql(u8, failure.code, "E_BORROW_MIXED");
    try std.testing.expect(known);
}

// Lowering drops a plain bytes or text `from` source of a borrowed record (`build.zig` `lendingSources`): sound only while
// no data of that parameter can reach the result. A record built from it is new storage: the ownership checker refuses it as a
// borrow stored into a new value (`E_SINGLE_OWNER_BORROW`) or as a mixed return (`E_BORROW_MIXED`), whichever it meets first;
// `selka check` reports both.
test "SK a record that holds a plain bytes or text `from` source is refused, whole or in an option" {
    try expectNewStorageRefused(std.testing.allocator, lent_bytes ++
        \\func make(block: Block, ref_des: bytes) -> Inst from block, ref_des:
        \\    return Inst(ref_des=ref_des, value=block.instances[0].value)
        \\func main() -> int:
        \\    return 0
    );
    try expectNewStorageRefused(std.testing.allocator, lent_text ++
        \\func make(block: Block, ref_des: str) -> Inst from block, ref_des:
        \\    return Inst(ref_des=ref_des, value=block.instances[0].value)
        \\func main() -> int:
        \\    return 0
    );
    try expectNewStorageRefused(std.testing.allocator, lent_bytes ++
        \\func instance_of(block: Block, ref_des: bytes) -> Inst? from block, ref_des:
        \\    for inst in block.instances:
        \\        if inst.ref_des == ref_des:
        \\            return Some(inst)
        \\    return Some(Inst(ref_des=ref_des, value=ref_des))
        \\func main() -> int:
        \\    return 0
    );
    try expectNewStorageRefused(std.testing.allocator, lent_text ++
        \\func instance_of(block: Block, ref_des: str) -> Inst? from block, ref_des:
        \\    return Some(Inst(ref_des=ref_des, value=copy(block.instances[0].value)))
        \\func main() -> int:
        \\    return 0
    );
}

// FX16: a field of a call's lent result is returned under the callee's own contract (tests/lang/borrowed_results.selka runs the
// accepted shapes). The contract still has to be the right one: each wrong one below is refused at the check.
const fx16_nets =
    \\record Net:
    \\    name: str
    \\func pick(xs: Net[]) -> Net from xs:
    \\    return xs[0]
    \\func pick_second(xs: Net[], ys: Net[]) -> Net from ys:
    \\    return ys[0]
    \\func fresh(xs: Net[]) -> Net:
    \\    return Net(name="fresh")
    \\
;

test "FX16 a field of a call lent by another parameter than the caller declares is refused (E_BORROW_UNDECLARED)" {
    try expectRefusal(std.testing.allocator, fx16_nets ++
        \\func first_name(xs: Net[], ys: Net[]) -> str from xs:
        \\    return pick_second(xs, ys).name
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_UNDECLARED");
}

test "FX16 a field of a call's fresh result returned under `from xs` is refused as a borrow of a temporary" {
    try expectRefusal(std.testing.allocator, fx16_nets ++
        \\func first_name(xs: Net[]) -> str from xs:
        \\    return fresh(xs).name
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

test "FX16 a field of a local copy of a lent result returned under `from xs` is refused (E_OWN_MARKER)" {
    try expectRefusal(std.testing.allocator, fx16_nets ++
        \\func first_name(xs: Net[]) -> str from xs:
        \\    const c = copy(pick(xs))
        \\    return c.name
        \\func main() -> int:
        \\    return 0
    , "E_OWN_MARKER");
}

test "FX16 a field of a call's lent result returned under the callee's source is accepted, direct and bound" {
    try expectAccepted(std.testing.allocator, fx16_nets ++
        \\func first_name(xs: Net[]) -> str from xs:
        \\    return pick(xs).name
        \\func bound_name(xs: Net[]) -> str from xs:
        \\    const x = pick(xs)
        \\    return x.name
        \\func main() -> int:
        \\    const nets = [Net(name="a")]
        \\    return len(first_name(nets)) + len(bound_name(nets))
    );
}

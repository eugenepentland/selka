//! W2: an ownership refusal about a borrowing local, record or collection keeps its code, position and repair, and gains a
//! note at the statement that made it own (the probes of `experiments/language-goals-audit-20261111/probes`); `dump-typed`
//! says how each local holds its value; and a `mut` binding of an element that a later line writes gets no automatic copy.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const typed_dump = @import("typed_dump.zig");
const support = @import("test_support.zig");

const row_record =
    \\record Row:
    \\    name: str
    \\    tags: str[]
    \\
    \\
;

/// Every ownership refusal of `text`, rendered in `format` as `check` prints them; `work` holds each function's transient work.
fn rendered(a: std.mem.Allocator, work: std.mem.Allocator, text: []const u8, format: language.diagnostic_output.Format) ![]const u8 {
    const checked = try support.checkSource(a, text);
    try std.testing.expect(checked.passed);
    var report: std.ArrayList(u8) = .empty;
    try std.testing.expect(!try unique.validate(a, work, checked.program.?, checked.src.?, format, &report));
    return report.items;
}

/// Whether `haystack` contains `needle`.
fn has(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "W2 a fresh row appended later names that line as why the earlier append of a borrow needs a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try rendered(arena.allocator(), std.testing.allocator, row_record ++
        \\func main() -> int:
        \\    mut all: Row[] = []
        \\    append(mut all, Row(name="a", tags=["x"]))
        \\    mut hits: Row[] = []
        \\    for r in all:
        \\        if r.name == "a":
        \\            append(mut hits, r)
        \\    append(mut hits, Row(name="z", tags=[]))
        \\    return len(hits)
        \\
    , .text);
    try std.testing.expect(has(text, ":11:30: error[E_SINGLE_OWNER_OVERLAP]: 'r' borrows from 'all'; copy it with copy(value)"));
    try std.testing.expect(has(text, ":12:5: `hits` owns its elements because this line stores a new value in it, so the earlier line needs `copy(...)` or `own`"));
}

test "W2 a write to the lender below the loop is the cause note of the refused append" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try rendered(arena.allocator(), std.testing.allocator, row_record ++
        \\func count(rows: Row[]) -> int:
        \\    return len(rows)
        \\
        \\func main() -> int:
        \\    mut all: Row[] = []
        \\    append(mut all, Row(name="a", tags=["x"]))
        \\    mut hits: Row[] = []
        \\    for r in all:
        \\        if r.name == "a":
        \\            append(mut hits, r)
        \\    append(mut all, Row(name="c", tags=[]))
        \\    return count(hits)
        \\
    , .text);
    try std.testing.expect(has(text, ":14:30: error[E_SINGLE_OWNER_OVERLAP]: 'r' borrows from 'all'"));
    try std.testing.expect(has(text, ":15:5: `hits` must own its elements because of this line ('all' cannot be changed or moved while 'hits' borrows it), so the earlier line needs `copy(...)` or `own`"));
}

test "W2 a later own move of a record of borrows is the cause note of the refused constructor field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try rendered(arena.allocator(), std.testing.allocator, row_record ++
        \\func keep(own r: Row) -> int:
        \\    return len(r.tags)
        \\
        \\func main() -> int:
        \\    const n = "a"
        \\    const t = ["x"]
        \\    const r = Row(name=n, tags=t)
        \\    const s = Row(name="b", tags=["y"])
        \\    const a = keep(own s)
        \\    const b = keep(own r)
        \\    return a + b
        \\
    , .text);
    try std.testing.expect(has(text, ":11:24: error[E_OWN_MARKER]: a bare `n` only lends the local `n`"));
    try std.testing.expect(has(text, ":14:20: `r` must own its fields because of this line (`r` is lent by the local `n` or the local `t`, " ++
        "and the `own` parameter `r` of `keep` needs its own value), so the earlier line needs `copy(...)` or `own`"));
}

test "W2 a managed field default names the field and the record's declaration in the refusal's note" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record R:
        \\    s: str
        \\    tags: str[] = []
        \\func size(r: R) -> int:
        \\    return len(r.s) + len(r.tags)
        \\func main() -> int:
        \\    const names = ["ab", "cd"]
        \\    const r = R(s=names[1])
        \\    return size(r)
        \\
    ;
    const text = try rendered(arena.allocator(), std.testing.allocator, source, .text);
    try std.testing.expect(has(text, ":8:19: error[E_SINGLE_OWNER_BORROW]: `names[1]` is lent by the local `names`, and field `s` of `R` needs its own value"));
    try std.testing.expect(has(text, ":3:5: field `tags` of `R` defaults to a new value, so `R(...)` without `tags` owns its fields instead of borrowing them; that is why the refused field needs `copy(...)` or `own`"));
    // The note travels in diagnostic-v1 as its own role, beside the unchanged copy repair.
    const json = try rendered(arena.allocator(), std.testing.allocator, source, .json);
    try std.testing.expect(has(json, "\"notes\":[{\"role\":\"cause\",\"message\":\"field `tags` of `R` defaults to a new value"));
    try std.testing.expect(has(json, "\"text\":\"copy(\""));
}

test "FR19 a generic record in a refusal and in its note is named as the source names it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record R[T]:
        \\    s: str
        \\    n: T
        \\    tags: str[] = []
        \\func size(r: R[int]) -> int:
        \\    return len(r.s) + len(r.tags)
        \\func main() -> int:
        \\    const names = ["ab", "cd"]
        \\    const r = R[int](s=names[1], n=1)
        \\    return size(r)
        \\
    ;
    const text = try rendered(arena.allocator(), std.testing.allocator, source, .text);
    try std.testing.expect(has(text, "and field `s` of `R[int]` needs its own value"));
    try std.testing.expect(has(text, "field `tags` of `R[int]` defaults to a new value, so `R[int](...)` without `tags` owns its fields"));
    try std.testing.expect(!has(text, "i64"));
}

test "W2 a refusal the as-owner re-check does not replace keeps its own note and gains no cause" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try rendered(arena.allocator(), std.testing.allocator, row_record ++
        \\func my_take(own rows: Row[]) -> int:
        \\    return len(rows)
        \\
        \\func main() -> int:
        \\    mut all: Row[] = []
        \\    append(mut all, Row(name="a", tags=["x"]))
        \\    const n = my_take(own all)
        \\    return n + len(all)
        \\
    , .text);
    try std.testing.expect(has(text, "'all' is moved here"));
    try std.testing.expect(!has(text, "because"));
}

test "W2 dump-typed says which locals own and which borrow, and from what" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a, row_record ++
        \\record R:
        \\    s: str
        \\    n: int = 0
        \\
        \\func count(rows: Row[]) -> int:
        \\    return len(rows)
        \\
        \\func main() -> int:
        \\    mut all: Row[] = []
        \\    append(mut all, Row(name="a", tags=["x"]))
        \\    mut hits: Row[] = []
        \\    for r in all:
        \\        if r.name == "a":
        \\            append(mut hits, r)
        \\    const names = ["ab", "cd"]
        \\    const kept = R(s=names[1])
        \\    return count(hits) + kept.n
        \\
    );
    const text = try typed_dump.render(a, program, null);
    try std.testing.expect(has(text, " rows: List<Row> borrows from the caller\n"));
    try std.testing.expect(has(text, " all: List<Row> mut owns\n"));
    try std.testing.expect(has(text, " hits: List<Row> mut borrows elements from all\n"));
    try std.testing.expect(has(text, " r: Row borrows from all\n"));
    try std.testing.expect(has(text, " names: List<str> owns\n"));
    try std.testing.expect(has(text, " kept: R borrows fields from names\n"));
}

const item_record =
    \\record Item:
    \\    name: str
    \\    count: int
    \\
    \\
;

test "W2 a mut binding of an element a later line writes through gets both spellings and no automatic copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `experiments/implicit-code-audit-20261111/probes/lost_update_on_copy.my` without its two `copy(...)`.
    const json = try rendered(a, std.testing.allocator, item_record ++
        \\func bump(mut items: Item[]):
        \\    mut first = items[0]
        \\    first.count = first.count + 1
        \\
        \\func main() -> int:
        \\    mut items: Item[] = []
        \\    append(mut items, Item(name="a", count=1))
        \\    bump(mut items)
        \\    return items[0].count
        \\
    , .json);
    try std.testing.expect(has(json, "a copy would keep this write out of `items[0]`, so no repair is automatic: " ++
        "write `mut first = copy(items[0])` if `first` is a private copy, or change `items[0]` itself (or store `first` back into it)"));
    try std.testing.expect(!has(json, "\"fix\""));
    // Refused at the binding, the message names the line of the later write.
    const twice = try rendered(a, std.testing.allocator, item_record ++
        \\func bump(mut items: Item[]) -> int:
        \\    mut x = items[0]
        \\    if len(items) > 1:
        \\        x = items[1]
        \\    x.count = 3
        \\    return x.count
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , .json);
    try std.testing.expect(has(twice, "a copy would keep the write to `x` at line 9 out of `items[0]`, so no repair is automatic"));
    try std.testing.expect(!has(twice, "\"fix\""));
}

test "W2 a binding never written through, or of a read-only parameter's element, keeps its copy repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unwritten = try rendered(a, std.testing.allocator, item_record ++
        \\func churn(mut items: Item[]) -> int:
        \\    mut item = items[0]
        \\    items[0] = Item(name="b", count=9)
        \\    return item.count
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , .json);
    try std.testing.expect(has(unwritten, "write `copy(items[0])` to keep both"));
    try std.testing.expect(has(unwritten, "\"text\":\"copy(\""));
    // A plain parameter cannot be changed, so the copy is the one meaning of the write.
    const readonly = try rendered(a, std.testing.allocator, item_record ++
        \\func first(items: Item[]) -> int:
        \\    mut head = items[0]
        \\    head.count = head.count + 1
        \\    return head.count
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , .json);
    try std.testing.expect(has(readonly, "write `mut head = copy(items[0])` to keep both"));
    try std.testing.expect(has(readonly, "\"text\":\"copy(\""));
}

test "W2 a loop variable added to a set reached through a field is advised sets.include without a wrong set name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const field = try rendered(a, std.testing.allocator,
        \\import sets
        \\
        \\record Holder:
        \\    seen: set[str]
        \\
        \\func main() -> int:
        \\    const names = ["a", "b", "a"]
        \\    mut h = Holder(seen=set())
        \\    for e in names:
        \\        sets.add(mut h.seen, e)
        \\    return len(h.seen)
        \\
    , .text);
    try std.testing.expect(has(field, "'e' borrows from 'names'; pass `e` to `sets.include` to keep both (it copies `e` only when the set does not hold it yet), or finish the borrow first"));
    const plain = try rendered(a, std.testing.allocator,
        \\import sets
        \\
        \\func main() -> int:
        \\    const names = ["a", "b", "a"]
        \\    mut seen: set[str] = set()
        \\    for e in names:
        \\        sets.add(mut seen, e)
        \\    return len(seen)
        \\
    , .text);
    try std.testing.expect(has(plain, "'e' borrows from 'names'; write `sets.include(mut seen, e)` to keep both"));
}

/// The entry point the programs of the set-store tests end with.
const main_function = "\nfunc main() -> int:\n    return 0\n";

/// Require the JSON diagnostics of `source`, which holds one refused store with `needle` as its call text, to carry one edit that
/// renames the `add` of that call to `include` and no `copy(` edit.
fn expectIncludeRename(a: std.mem.Allocator, work: std.mem.Allocator, source: []const u8, needle: []const u8) !void {
    const json = try rendered(a, work, try std.mem.concat(a, u8, &.{ source, main_function }), .json);
    const at = std.mem.indexOf(u8, source, needle).? + "sets.".len;
    const edit = try std.fmt.allocPrint(a, "\"bytes\":{{\"start\":{d},\"end\":{d}}},\"text\":\"include\"", .{ at, at + "add".len });
    try std.testing.expect(has(json, edit));
    try std.testing.expect(!has(json, "\"text\":\"copy(\""));
}

test "FX2 a lent value stored in a set is repaired by one rename to sets.include, not by a copy that needs a second round" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const head = "import sets\n\nrecord Entry:\n    key: str\n\nrecord Holder:\n    seen: set[str]\n\n";
    const loop_field = "func f(entries: Entry[]) -> int:\n    mut seen: set[str] = set()\n    for e in entries:\n        sets.add(mut seen, e.key)\n    return len(seen)\n";
    const loop_name = "func f(names: str[]) -> int:\n    mut seen: set[str] = set()\n    for name in names:\n        sets.add(mut seen, name)\n    return len(seen)\n";
    const parameter = "func f(word: str) -> int:\n    mut seen: set[str] = set()\n    sets.add(mut seen, word)\n    return len(seen)\n";
    const element = "func f(names: str[]) -> int:\n    mut seen: set[str] = set()\n    for i in range(len(names)):\n        sets.add(mut seen, names[i])\n    return len(seen)\n";
    const through_field = "func f(names: str[]) -> int:\n    mut h = Holder(seen=set())\n    for e in names:\n        sets.add(mut h.seen, e)\n    return len(h.seen)\n";
    const mut_parameter = "func f(mut seen: set[str], entries: Entry[]) -> int:\n    for e in entries:\n        sets.add(mut seen, e.key)\n    return len(seen)\n";
    const work = std.testing.allocator;
    try expectIncludeRename(a, work, head ++ loop_field, "sets.add(mut seen, e.key)");
    try expectIncludeRename(a, work, head ++ loop_name, "sets.add(mut seen, name)");
    try expectIncludeRename(a, work, head ++ parameter, "sets.add(mut seen, word)");
    try expectIncludeRename(a, work, head ++ element, "sets.add(mut seen, names[i])");
    try expectIncludeRename(a, work, head ++ through_field, "sets.add(mut h.seen, e)");
    try expectIncludeRename(a, work, head ++ mut_parameter, "sets.add(mut seen, e.key)");
}

test "FX2 a lent element a write needs a private copy of keeps the copy repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const json = try rendered(a, std.testing.allocator, item_record ++ "func first(items: Item[]) -> int:\n    mut head = items[0]\n    head.count = head.count + 1\n    return head.count\n" ++ main_function, .json);
    try std.testing.expect(has(json, "\"text\":\"copy(\""));
    try std.testing.expect(!has(json, "\"text\":\"include\""));
}

test "W2 a mut local that borrows its places owns once a later line stores a new value, and that line is the note" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try rendered(arena.allocator(), std.testing.allocator, row_record ++
        \\func main() -> int:
        \\    mut all: Row[] = []
        \\    append(mut all, Row(name="a", tags=["x"]))
        \\    append(mut all, Row(name="b", tags=["y"]))
        \\    mut best = all[0]
        \\    for i in range(len(all)):
        \\        if all[i].name == "b":
        \\            best = all[i]
        \\    best = Row(name="z", tags=[])
        \\    return len(best.name)
        \\
    , .text);
    try std.testing.expect(has(text, ":9:16: error[E_SINGLE_OWNER_BORROW]: `all[0]` is lent by the local `all`, and the `mut` local `best` needs its own value"));
    try std.testing.expect(has(text, ":13:5: `best` owns its value because this line stores a new value in it, so the earlier line needs `copy(...)` or `own`"));
    // The second refusal, after the first one's copy, still names the source's fresh store, not that copy.
    try std.testing.expect(!has(text, ":9:5: `best` owns its value"));
}

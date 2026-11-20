//! FR11 (friction F-16, F-24, F-55, F-56): the shapes next to the ones the checker now accepts stay refused, each with
//! the message that says why, and an element moved out of a new list traps exactly as the index it replaces.
const std = @import("std");
const t = std.testing;
const options = @import("test_paths");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// Check `source` with the compiler and require exit 1 with `code` and every fragment in its diagnostics.
fn refusedWith(source: []const u8, code: []const u8, fragments: []const []const u8) !void {
    try refusedWithout(source, code, fragments, &.{});
}

/// `refusedWith`, and none of `absent` is in the message.
fn refusedWithout(source: []const u8, code: []const u8, fragments: []const []const u8, absent: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "shape.selka", .data = source });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "shape.selka" });
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", path, "--no-cache" } });
    try t.expect(result.term == .exited and result.term.exited == 1);
    try t.expect(std.mem.indexOf(u8, result.stderr, code) != null);
    for (fragments) |fragment| try t.expect(std.mem.indexOf(u8, result.stderr, fragment) != null);
    for (absent) |fragment| try t.expect(std.mem.indexOf(u8, result.stderr, fragment) == null);
}

const rows =
    \\record Row:
    \\    name: str
    \\
    \\
    \\func rows() -> Row[]:
    \\    return [Row(name="a"), Row(name="b")]
    \\
    \\
    \\func first(lists: Row[][]) -> Row[] from lists:
    \\    return lists[0]
    \\
    \\
;

// FR25 item 3: a text slice of a field of a record constructor is read within the statement and accepted; one that is bound,
// stored or returned would outlive the temporary and stays refused, and the message says to bind the record first.
test "a text slice of a field of a record constructor is read in place, and a bound, stored or returned one is refused" {
    const record = "record Name:\n    text: str\n\n\n";
    // FR27: the advice to bind the record first is given where it helps (a name), and says what the expression reads; a stored
    // slice stays a slice of the local, and a returned value would outlive it, so those two say only `copy(...)`.
    const advice = "bind the record to a local first and slice that local's field";
    const bound = record ++ "func main() -> int:\n    const piece = Name(text=\"hello\").text[0:2]\n    return len(piece)\n";
    const stored = record ++ "func main() -> int:\n    mut parts: str[] = []\n    append(mut parts, Name(text=\"hello\").text[0:2])\n    return len(parts)\n";
    const returned = record ++ "func head() -> str:\n    return Name(text=\"hello\").text[0:2]\n\n\nfunc main() -> int:\n    return len(head())\n";
    const copy_advice = "write `copy(Name(text=\"hello\").text[0:2])` to keep both";
    try refusedWith(bound, "E_SLICE_ESCAPES", &.{ "is lent by a temporary value", "the local `piece`", advice });
    try refusedWithout(stored, "E_SLICE_ESCAPES", &.{ "the list `parts`", copy_advice }, &.{"bind the record"});
    try refusedWithout(returned, "E_SLICE_ESCAPES", &.{ "the returned value", copy_advice }, &.{"bind the record"});
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "slice.selka", .data = record ++ "func main() -> int:\n    return len(Name(text=\"hello\").text[0:2]) + len(copy(Name(text=\"hello\").text[1:3]))\n" });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", try std.fs.path.join(a, &.{ root, "slice.selka" }), "--no-cache" } });
    try t.expect(result.term == .exited and result.term.exited == 0);
}

// FR27: an element of a fresh record's list field is not a slice, so the advice to bind the record first says to read the
// element, for a name and for a store; a returned element says only `copy(...)`.
test "the advice to bind a fresh record first names what is read: an element is read, not sliced" {
    const bag = "record Bag:\n    items: str[]\n\n\n";
    const advice = "bind the record to a local first and read the element from that local";
    const bound = bag ++ "func main() -> int:\n    const piece = Bag(items=[\"a\"]).items[0]\n    return len(piece)\n";
    const stored = bag ++ "func main() -> int:\n    mut parts: str[] = []\n    append(mut parts, Bag(items=[\"a\"]).items[0])\n    return len(parts)\n";
    const returned = bag ++ "func head() -> str:\n    return Bag(items=[\"a\"]).items[0]\n\n\nfunc main() -> int:\n    return len(head())\n";
    const sliced = "slice that local's field";
    try refusedWithout(bound, "E_SINGLE_OWNER_BORROW", &.{ "is lent by a temporary value", "the local `piece`", advice }, &.{sliced});
    try refusedWithout(stored, "E_SINGLE_OWNER_BORROW", &.{ "the list `parts`", advice }, &.{sliced});
    try refusedWithout(returned, "E_SINGLE_OWNER_BORROW", &.{ "the returned value", "write `copy(Bag(items=[\"a\"]).items[0])` to keep both" }, &.{"bind the record"});
}

// FR28, FR69: a slice of an element of a fresh record is refused for a `const` and a `mut` binding alike, and the advice is to bind the
// record to a local first: the slice of an element of that local is a view, bound to a `const` as the slice of its field is.
test "the advice for a slice of an element of a fresh record is to bind the record, and what it says checks" {
    const bag = "record Bag:\n    items: str[]\n\n\nfunc made() -> Bag:\n    return Bag(items=[\"abc\"])\n\n\n";
    const advice = "bind the record to a local first and slice that local's field";
    const bound = bag ++ "func main() -> int:\n    const piece = made().items[0][0:1]\n    return len(piece)\n";
    const mutable = bag ++ "func main() -> int:\n    mut piece = made().items[0][0:1]\n    return len(piece)\n";
    try refusedWith(bound, "E_SLICE_ESCAPES", &.{ "is lent by a temporary value", "the local `piece`", advice });
    try refusedWithout(bound, "E_SLICE_ESCAPES", &.{"is lent by a temporary value"}, &.{ "another local", "cannot hold a slice of an element" });
    try refusedWithout(mutable, "E_SLICE_ESCAPES", &.{ "the `mut` local `piece`", advice }, &.{"another local"});
    // What the advice says to write checks, as the two-step form, the `mut` binding and the copy do.
    try checksClean(bag ++ "func main() -> int:\n    const record = made()\n    const piece = record.items[0][0:1]\n    return len(piece)\n");
    try checksClean(bag ++ "func main() -> int:\n    const record = made()\n    const item = record.items[0]\n    const piece = item[0:1]\n    return len(piece)\n");
    try checksClean(bag ++ "func main() -> int:\n    const record = made()\n    mut piece = record.items[0][0:1]\n    return len(piece)\n");
    try checksClean(bag ++ "func main() -> int:\n    const piece = copy(made().items[0][0:1])\n    return len(piece)\n");
}

// FX14: a loop's element is a compiler local too, but the loop initializes it before the statement, so a slice of its field bound
// to a name is the view binding it was before FR25 (no copy); only the hidden owner a slice makes for a fresh record is refused.
const nets =
    \\record Net:
    \\    name: bytes
    \\    label: str
    \\
    \\
    \\record Board:
    \\    nets: Net[]
    \\
    \\
    \\func made() -> Net[]:
    \\    return [Net(name=b"abcd", label="xy"), Net(name=b"ef", label="z")]
    \\
    \\
;

test "a slice of a loop element's field bound to a name is a view, as before FR25, over a parameter, a field and a local" {
    try checksClean(nets ++
        \\func over_parameter(xs: Net[]) -> int:
        \\    mut total = 0
        \\    for net in xs:
        \\        const suffix = net.name[1:]
        \\        const part = net.label[0:1]
        \\        total = total + len(suffix) + len(part)
        \\    return total
        \\
        \\
        \\func over_field(board: Board) -> int:
        \\    mut total = 0
        \\    for net in board.nets:
        \\        const suffix = net.name[len(b"a"):]
        \\        total = total + len(suffix)
        \\    return total
        \\
        \\
        \\func over_local() -> int:
        \\    const xs = made()
        \\    mut total = 0
        \\    for i, net in enumerate(xs):
        \\        const suffix = net.label[1:]
        \\        total = total + len(suffix) + i
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return over_parameter(made()) + over_field(Board(nets=made())) + over_local()
        \\
    );
    // The fresh record of FR25 item 3 stays refused, and a call's result declared `from` a parameter names that parameter.
    try refusedWith(nets ++
        \\func main() -> int:
        \\    const piece = Net(name=b"abc", label="x").name[0:2]
        \\    return len(piece)
        \\
    , "E_SLICE_ESCAPES", &.{ "is lent by a temporary value", "bind the record to a local first" });
    try refusedWith(nets ++
        \\func pick(xs: Net[]) -> Net from xs:
        \\    return xs[0]
        \\
        \\
        \\func f(xs: Net[]) -> int:
        \\    const piece = pick(xs).name[1:]
        \\    return len(piece)
        \\
        \\
        \\func main() -> int:
        \\    return f(made())
        \\
    , "E_SLICE_ESCAPES", &.{"is lent by the plain parameter `xs`"});
}

test "a view through a loop element holds its source: a change while it is live is refused, and it cannot leave the body" {
    // The list is written while the view is live.
    try refusedWith(nets ++
        \\func main() -> int:
        \\    mut xs = made()
        \\    mut total = 0
        \\    for net in xs:
        \\        const suffix = net.name[1:]
        \\        xs[0] = Net(name=b"zz", label="q")
        \\        total = total + len(suffix)
        \\    return total
        \\
    , "E_SLICE_ESCAPES", &.{ "the write to `xs[0]` at line", "while `suffix` is still read after it; finish with `suffix` before line" });
    // After the loop the name is out of scope, and it cannot be kept in a name declared outside the loop.
    try refusedWith(nets ++
        \\func main() -> int:
        \\    const xs = made()
        \\    for net in xs:
        \\        const suffix = net.name[1:]
        \\    return len(suffix)
        \\
    , "E_UNKNOWN_NAME", &.{});
    try refusedWith(nets ++
        \\func main() -> int:
        \\    const xs = made()
        \\    mut keep: bytes = b""
        \\    for net in xs:
        \\        const suffix = net.name[1:]
        \\        keep = suffix
        \\    return len(keep)
        \\
    , "E_SINGLE_OWNER_OVERLAP", &.{"'suffix' borrows from 'xs'"});
    // `for x in own xs:` makes the name an owner; the slice is a view of it, so moving the element while the view is live is
    // refused and moving it after the view's last use is accepted.
    const eat =
        \\func eat(own n: Net) -> int:
        \\    return len(n.name)
        \\
        \\
        \\
    ;
    try refusedWith(nets ++ eat ++
        \\func main() -> int:
        \\    mut total = 0
        \\    for net in own made():
        \\        const suffix = net.name[1:]
        \\        total = total + eat(own net)
        \\        total = total + len(suffix)
        \\    return total
        \\
    , "E_SLICE_ESCAPES", &.{ "`net` is given away at line", "use `suffix` before line" });
    try checksClean(nets ++ eat ++
        \\func main() -> int:
        \\    mut total = 0
        \\    for net in own made():
        \\        const suffix = net.name[1:]
        \\        total = total + len(suffix)
        \\        total = total + eat(own net)
        \\    return total
        \\
    );
}
// FR26 item 3: a name cannot hold a bare slice of a `byte_buffer` (a buffer can grow under a borrowed one), and `selka check`
// says so instead of leaving the build to stop with E_CORE_UNSUPPORTED (FR27: the slice is a new buffer, `copy(...)` names it); the slice read in place, a `bytes` slice and
// `bytes(buf[a:b])` are accepted.
fn refusedBufferSlice(source: []const u8, fragment: []const u8) !void {
    try refusedWith(source, "E_BUFFER_SLICE_NAME", &.{ "a slice of a `byte_buffer` is a new buffer of that range", "can grow under a borrowed slice", fragment });
}

test "a name bound to a slice of a byte_buffer is refused at the check and the message names bytes(...)" {
    const head = "func main() -> int:\n    mut buf = byte_buffer([120, 97, 122, 97])\n";
    try refusedBufferSlice(head ++ "    const piece = buf[1:3]\n    return len(piece)\n", "the name `piece` cannot hold it bare; write `copy(buf[1:3])` for a buffer of the range or `bytes(buf[1:3])` for its octets");
    try refusedBufferSlice(head ++ "    mut part = buf[0:1]\n    return len(part)\n", "the name `part` cannot hold it bare; write `copy(buf[0:1])` for a buffer of the range or `bytes(buf[0:1])`");
    const loop = head ++ "    for step in range(2):\n        const piece = buf[step:step + 2]\n        if len(piece) > 5:\n            return 1\n    return 0\n";
    try refusedBufferSlice(loop, "write `copy(buf[step:step + 2])` for a buffer of the range or `bytes(buf[step:step + 2])`");
    const record = "record Frame:\n    data: byte_buffer\n\n\nfunc size(frame: Frame) -> int:\n    const piece = frame.data[0:2]\n    return len(piece)\n\n\n" ++
        "func main() -> int:\n    return size(Frame(data=byte_buffer([1, 2, 3])))\n";
    try refusedBufferSlice(record, "write `copy(frame.data[0:2])` for a buffer of the range or `bytes(frame.data[0:2])`");
}

test "a slice of a byte_buffer read in place, a bytes slice and bytes(buf[a:b]) are accepted beside the refused names (FR26)" {
    const head = "func main() -> int:\n    mut buf = byte_buffer([120, 97, 122, 97])\n";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const accepted = head ++ "    const kept = bytes(buf[1:3])\n    const data = b\"abcd\"\n    const view = data[1:3]\n    mut total = len(buf[0:2]) + len(kept) + len(view)\n" ++
        "    for octet in buf[1:3]:\n        total += octet\n    if 97 in buf[1:3]:\n        total += 1\n    return total\n";
    try directory.dir.writeFile(t.io, .{ .sub_path = "reads.selka", .data = accepted });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", try std.fs.path.join(a, &.{ root, "reads.selka" }), "--no-cache" } });
    try t.expect(result.term == .exited and result.term.exited == 0);
}
// F-16: a call whose result is lent by its argument cannot be the list a consuming loop takes, and the message says so.
test "a consuming loop refuses a call whose list is lent by its argument and says by whom" {
    try refusedWith(rows ++
        \\func main() -> int:
        \\    const lists = [rows()]
        \\    mut n = 0
        \\    for row in own first(lists):
        \\        n += len(row.name)
        \\    return n
        \\
    , "E_SINGLE_OWNER_BORROW", &.{ "a consuming loop cannot own `first(lists)`", "the call returns is lent by the local `lists`", "for x in own copy(first(lists)):" });
}

// F-55: what stays refused next to an element of a new list: a list lent by a call, a field of a temporary element, and
// an element of a dictionary value read with `dicts.get`.
test "an element of a lent list, a field of a temporary element and a dictionary read stay refused" {
    try refusedWith(rows ++ "func main() -> int:\n    const lists = [rows()]\n    const row = first(lists)[0]\n    return len(row.name)\n", "E_SINGLE_OWNER_BORROW", &.{"is lent by the local `lists`"});
    try refusedWith(rows ++ "func main() -> int:\n    const name = rows()[1].name\n    return len(name)\n", "E_SINGLE_OWNER_BORROW", &.{"is lent by a temporary value"});
    try refusedWith("import dicts\n\n\nfunc main() -> int:\n    mut m: dict[str, str[]] = {}\n    m[\"k\"] = [\"v\"]\n    const none: str[] = []\n" ++
        "    const v = dicts.get(m, \"k\", none)[0]\n    return len(v)\n", "E_SINGLE_OWNER_BORROW", &.{"is lent by the local `m`"});
}

// F-55: the element moves out with `pop_at`, whose trap is the index's own: the same code, line and values.
test "an element of a new list traps out of range exactly as the index of a named list does" {
    const temporary =
        \\func make(n: int) -> str[]:
        \\    mut out: str[] = []
        \\    for i in range(n):
        \\        append(mut out, str(i))
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    const v = make(2)[4]
        \\    return len(v)
        \\
    ;
    const named =
        \\func make(n: int) -> str[]:
        \\    mut out: str[] = []
        \\    for i in range(n):
        \\        append(mut out, str(i))
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    const all = make(2)
        \\    return len(all[4])
        \\
    ;
    var moved = try language.Compilation.init(t.allocator, "moved.selka", temporary);
    defer moved.deinit();
    const first = try native.run(&moved);
    var read = try language.Compilation.init(t.allocator, "read.selka", named);
    defer read.deinit();
    const second = try native.run(&read);
    try t.expect(first.trapped() and second.trapped());
    try t.expectEqualStrings("R_LIST_BOUNDS", first.trap.code);
    try t.expectEqualStrings(second.trap.code, first.trap.code);
    try t.expectEqual(@as(u64, 9), first.trap.line);
    try t.expectEqualDeep(second.trap.detail, first.trap.detail);
}

const work =
    \\record Work:
    \\    lines: str[]
    \\    targets: str[]
    \\
    \\
    \\enum Slot:
    \\    busy(work: Work)
    \\    idle
    \\
    \\
    \\func emit(mut work: Work, statement: str):
    \\    append(mut work.lines, copy(statement))
    \\
    \\
    \\func last(work: Work) -> str from work:
    \\    return work.targets[0]
    \\
    \\
    \\func text(mut line: str, statement: str):
    \\    line = copy(statement)
    \\
    \\
;

// F-24: next to `mut work`, an argument that lends a part of `work` stays refused and is named with the copy that frees
// it; a `mut` list element and a second `mut` of the record keep their refusals.
test "an argument that lends a part of a record passed mut and a mut element stay refused" {
    const entry = "func main() -> int:\n    mut work = Work(lines=[], targets=[\"out\"])\n";
    try refusedWith(work ++ entry ++ "    emit(mut work, work.targets[0])\n    return len(work.lines)\n", "E_SINGLE_OWNER_OVERLAP", &.{
        "'work.targets[0]' lends a part of 'work' to the call", "Pass a value of its own (`copy(work.targets[0])`)",
    });
    try refusedWith(work ++ entry ++ "    emit(mut work, last(work))\n    return len(work.lines)\n", "E_SINGLE_OWNER_OVERLAP", &.{"'last(work)' lends a part of 'work'"});
    try refusedWith(work ++ entry ++ "    text(mut work.lines[0], \"x\" + last(work))\n    return 0\n", "E_SINGLE_OWNER_OVERLAP", &.{"may be the same list element"});
}

// FR75: a `match mut` payload binding passed `mut` names a place in the matched owner, so F-24's rule reaches it: a read
// argument that makes a value of its own is made before Core takes the payload out of its case, and the call gives what
// the record form gives. An argument that lends a part stays refused with F-24's message, and so does the value-making
// one when the matched place is a list element.
test "a value-making argument beside a match mut binding passed mut runs as its record form, and a lent part stays refused" {
    const arm = "        case busy(work=held):\n            emit(mut held, ";
    const tail = ")\n            print(out, held.lines)\n        case idle:\n            pass\n";
    const slot = "func main(out: Stream) -> int:\n    mut slot = Slot.busy(work=Work(lines=[], targets=[\"t\"]))\n    match mut slot:\n";
    const binding = work ++ slot ++ arm ++ "copy(held.targets[0]) + \"?\"" ++ tail ++ "    return 0\n";
    const record = work ++ "func main(out: Stream) -> int:\n    mut held = Work(lines=[], targets=[\"t\"])\n" ++
        "    emit(mut held, copy(held.targets[0]) + \"?\")\n    print(out, held.lines)\n    return 0\n";
    try checksClean(binding);
    var matched = try language.Compilation.init(t.allocator, "binding.selka", binding);
    defer matched.deinit();
    const first = try native.run(&matched);
    var plain = try language.Compilation.init(t.allocator, "record.selka", record);
    defer plain.deinit();
    const second = try native.run(&plain);
    try t.expect(!first.trapped() and !second.trapped());
    try t.expectEqualStrings("['t?']\n", second.stdout);
    try t.expectEqualStrings(second.stdout, first.stdout);
    const lent = work ++ slot ++ arm;
    try refusedWith(lent ++ "held.targets[0]" ++ tail ++ "    return 0\n", "E_SINGLE_OWNER_OVERLAP", &.{"'held.targets[0]' lends a part of 'slot' to the call"});
    try refusedWith(lent ++ "last(held)" ++ tail ++ "    return 0\n", "E_SINGLE_OWNER_OVERLAP", &.{"'last(held)' lends a part of 'slot'"});
    const element = "func main(out: Stream) -> int:\n    mut slots = [Slot.busy(work=Work(lines=[], targets=[\"t\"]))]\n    match mut slots[0]:\n";
    try refusedWith(work ++ element ++ arm ++ "copy(held.targets[0]) + \"?\"" ++ tail ++ "    return 0\n", "E_SINGLE_OWNER_OVERLAP", &.{"may be the same list element"});
}

const parsed =
    \\record Options:
    \\    problem: str
    \\    items: str[]
    \\
    \\
    \\func parse(text: str) -> Options:
    \\    return Options(problem=copy(text), items=[copy(text)])
    \\
    \\
;

// F-56: `in` reads a field of a call's result as `==` does; a list's membership stays removed, and a binding that would
// keep the field still needs its own value.
test "membership of a list field and a binding of a field of a call's result stay refused" {
    try refusedWith(parsed ++ "func main() -> int:\n    if \"a\" in parse(\"a\").items:\n        return 1\n    return 0\n", "E_LIST_MEMBERSHIP_REMOVED", &.{"lists.contains"});
    try refusedWith(parsed ++ "func main() -> int:\n    const problem = parse(\"a\").problem\n    return len(problem)\n", "E_SINGLE_OWNER_BORROW", &.{
        "is lent by a temporary value", "copy(parse(\"a\").problem)",
    });
}

const records =
    \\record R:
    \\    name: str
    \\    tags: str[]
    \\    inner: Inner
    \\
    \\
    \\record Inner:
    \\    label: str
    \\
    \\
    \\func pick_b(a: R, b: R) -> str from b:
    \\    return b.name
    \\
    \\
    \\func pick_c(a: R, b: R, c: R) -> str from c:
    \\    return c.name
    \\
    \\
    \\func echo(text: str) -> str from text:
    \\    return text
    \\
    \\
    \\func two(mut a: R, mut b: R, text: str) -> int:
    \\    b.name = "a much longer replacement text that needs new storage"
    \\    a.name = copy(text)
    \\    return len(text)
    \\
    \\
    \\func three(mut a: R, mut b: R, mut c: R, text: str) -> int:
    \\    c.name = "a much longer replacement text that needs new storage"
    \\    return len(text)
    \\
    \\
    \\func fields(mut x: Inner, mut y: Inner, text: str) -> int:
    \\    y.label = "a much longer replacement text that needs new storage"
    \\    return len(text)
    \\
    \\
    \\func make(name: str) -> R:
    \\    return R(name=copy(name), tags=[copy(name)], inner=Inner(label=copy(name)))
    \\
    \\
    \\func main() -> int:
    \\    mut a = make("a")
    \\    mut b = make("b")
    \\    mut c = make("c")
    \\
;

// F-24 (the coordinator's review of 14 November): a value that borrows from the second or third record passed `mut`
// is refused, not only one that borrows from the first; through a nested call and a `mut` field path too.
test "an argument that borrows from any of several records passed mut is refused and named" {
    try refusedWith(records ++ "    return two(mut a, mut b, pick_b(a, b))\n", "E_SINGLE_OWNER_OVERLAP", &.{"'pick_b(a, b)' lends a part of 'b' to the call"});
    try refusedWith(records ++ "    return three(mut a, mut b, mut c, pick_c(a, b, c))\n", "E_SINGLE_OWNER_OVERLAP", &.{"lends a part of 'c'"});
    try refusedWith(records ++ "    return three(mut a, mut b, mut c, pick_b(a, b))\n", "E_SINGLE_OWNER_OVERLAP", &.{"lends a part of 'b'"});
    try refusedWith(records ++ "    return fields(mut a.inner, mut b.inner, pick_b(a, b))\n", "E_SINGLE_OWNER_OVERLAP", &.{"lends a part of 'b'"});
    try refusedWith(records ++ "    return two(mut a, mut b, echo(pick_b(a, b)))\n", "E_SINGLE_OWNER_OVERLAP", &.{"'echo(pick_b(a, b))' lends a part of 'b'"});
    // The coordinator's program: the second `mut` record lends the text, and the callee replaces it before the read.
    try refusedWith(records ++ "    const n = two(mut a, mut b, pick_b(a, b))\n    return n + len(a.name)\n", "E_SINGLE_OWNER_OVERLAP", &.{
        "the earlier argument 'b' passes 'b' `mut`", "Pass a value of its own (`copy(pick_b(a, b))`)",
    });
}

const options_source =
    \\record Name:
    \\    text: str
    \\
    \\
    \\record Box:
    \\    name: str?
    \\
    \\
    \\func maybe() -> str?:
    \\    return Some("x" + "y")
    \\
    \\
    \\func pick(b: Box) -> str? from b:
    \\    return b.name
    \\
    \\
;

// F-71: an option someone else holds keeps today's lend. A local the function owns, and an `own` parameter, name the
// `options.take_or` that moves the value; a field, a lent call and a plain parameter name only the copy.
test "unwrap_or on an owned local option names options.take_or, and on a field or a lent call only the copy" {
    try refusedWith(options_source ++
        \\func main() -> int:
        \\    const o = maybe()
        \\    const t = o.unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{ "is lent by the local `o`", "write `options.take_or(own o, \"\")` in place of `o.unwrap_or(\"\")`", "`copy(t)`" });
    try refusedWith(options_source ++
        \\func take_name(own o: str?) -> Name:
        \\    const t = o.unwrap_or("")
        \\    return Name(text=own t)
        \\
        \\
        \\func main() -> int:
        \\    return len(take_name(maybe()).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"`options.take_or(own o, \"\")`"});
    try refusedWith(options_source ++
        \\func main() -> int:
        \\    const b = Box(name=Some("p" + "q"))
        \\    const t = b.name.unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{ "is lent by the local `b`", "write `copy(t)` to keep both" });
    try refusedWith(options_source ++
        \\func main() -> int:
        \\    const b = Box(name=Some("p" + "q"))
        \\    const t = pick(b).unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{ "is lent by the local `b`", "write `copy(t)` to keep both" });
    try refusedWith(options_source ++
        \\func name_of(o: str?) -> Name:
        \\    const t = o.unwrap_or("")
        \\    return Name(text=own t)
        \\
        \\
        \\func main() -> int:
        \\    return len(name_of(maybe()).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{ "lent by the plain parameter `o`", "`copy(t)`" });
}

// F-71: a call's option with a default that is a place (a local, a field, a parameter) keeps today's lend: the result would
// be owned on one path and lent on the other. A `mut` binding keeps it too (D-F71-3), and `own` on the call stays refused.
test "unwrap_or of a call's option keeps its lend beside a place default, in a mut binding and under own" {
    try refusedWith(options_source ++
        \\func main() -> int:
        \\    const d = "d" + "e"
        \\    const t = maybe().unwrap_or(d)
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"is lent by the local `d`"});
    try refusedWith(options_source ++
        \\func name_of(n: Name) -> Name:
        \\    const t = maybe().unwrap_or(n.text)
        \\    return Name(text=own t)
        \\
        \\
        \\func main() -> int:
        \\    return len(name_of(Name(text="q")).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"lent by the plain parameter `n`"});
    try refusedWith(options_source ++
        \\func main() -> int:
        \\    mut t = maybe().unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"is lent by a temporary value"});
    try refusedWith(options_source ++
        \\func main() -> int:
        \\    const t = own maybe().unwrap_or("")
        \\    return len(t)
        \\
    , "E_OWN_MARKER", &.{"a fresh value is already owned"});
}

// F-71's adversarial probes that stay refused: an option lent by a generic `from` call, by a library call declared `from`
// its argument (`json.as_str`), a field of a call's result, a chain through a call lent `from` its argument, a default
// that is the receiver's own argument (a place), and a task's argument (tasks borrow, and a lent one is refused).
test "unwrap_or stays a lend for a generic or library from call, a temporary's field, a lent chain and a place default" {
    try refusedWith(options_source ++
        \\func first_of[T](xs: T?[]) -> T? from xs:
        \\    return xs[0]
        \\
        \\
        \\func main() -> int:
        \\    const xs: str?[] = [Some("a" + "b")]
        \\    const t = first_of(xs).unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"is lent by the local `xs`"});
    try refusedWith(
        \\import json
        \\
        \\record Name:
        \\    text: str
        \\
        \\
        \\func main() -> int:
        \\    const v = json.Json.text(value="a" + "b")
        \\    const t = json.as_str(v).unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"is lent by the local `v`"});
    try refusedWith(options_source ++
        \\func make() -> Box:
        \\    return Box(name=Some("p" + "q"))
        \\
        \\
        \\func main() -> int:
        \\    const t = make().name.unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"which only lends it"});
    try refusedWith(options_source ++
        \\func outer(o: str?) -> str? from o:
        \\    return o
        \\
        \\
        \\func main() -> int:
        \\    const t = outer(maybe()).unwrap_or("")
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"which only lends it"});
    try refusedWith(options_source ++
        \\func f(x: str) -> str?:
        \\    return Some(x + "!")
        \\
        \\
        \\func main() -> int:
        \\    const x = "ab" + "c"
        \\    const t = f(x).unwrap_or(x)
        \\    return len(Name(text=own t).text)
        \\
    , "E_SINGLE_OWNER_BORROW", &.{"is lent by the local `x`"});
    try refusedWith("import parallel\n\n" ++ options_source ++
        \\func size(s: str) -> int:
        \\    return len(s)
        \\
        \\
        \\func main() -> int:
        \\    mut total = 0
        \\    with parallel.group() as g:
        \\        const h = g.submit(size, maybe().unwrap_or(""))
        \\        total = h.result()
        \\    return total
        \\
    , "E_TASK_LOAN", &.{"write copy(...) around it"});
}

/// Check `source` with the compiler and require it to check cleanly (exit 0).
fn checksClean(source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "shape.selka", .data = source });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "shape.selka" });
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", path, "--no-cache" } });
    try t.expectEqualStrings("", if (std.mem.indexOf(u8, result.stderr, "error[") != null) result.stderr else "");
    try t.expect(result.term == .exited and result.term.exited == 0);
}

// F-71: a payload with no managed storage (a number, a record of numbers) is copied by the selection, as before: an owned
// reading would move a scalar, which Core refuses (`E_OWN_MARKER`). The port binds `level(x).unwrap_or(0.0)` this way.
test "unwrap_or of a call's option of a number or a record of numbers is bound as before" {
    try checksClean(
        \\record Point:
        \\    x: int
        \\
        \\
        \\func level(present: bool) -> float?:
        \\    if present:
        \\        return Some(1.5)
        \\    return None
        \\
        \\
        \\func point(present: bool) -> Point?:
        \\    if present:
        \\        return Some(Point(x=1))
        \\    return None
        \\
        \\
        \\func main() -> int:
        \\    const volts = level(True).unwrap_or(0.0)
        \\    const at = point(False).unwrap_or(Point(x=0))
        \\    if volts > 1.0:
        \\        return at.x
        \\    return 1
        \\
    );
}

// FR24 item 2: a read that keeps nothing of a record constructor is accepted (tests/lang/constructor_temporaries.selka), a
// binding of one of its fields would keep the temporary and stays refused, with the copy that keeps both.
test "a field of a record constructor bound to a local stays refused while a length of it checks" {
    const record = "record Bag:\n    items: str[]\n\n\n";
    try refusedWith(record ++ "func main() -> int:\n    const items = Bag(items=[\"x\", \"yy\"]).items\n    return len(items)\n", "E_SINGLE_OWNER_BORROW", &.{ "is lent by a temporary value", "copy(Bag(items=" });
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "length.selka", .data = record ++ "func main() -> int:\n    return len(Bag(items=[\"x\", \"yy\"]).items)\n" });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", try std.fs.path.join(a, &.{ root, "length.selka" }), "--no-cache" } });
    try t.expect(result.term == .exited and result.term.exited == 0);
}

//! The ownership analysis on hand-written functions with known answers
//! (`OWNERSHIP-ANALYSIS-1`), read through the explain surface
//! (`OWNERSHIP-EXPLAIN-1`) exactly as `mylang check --explain-ownership` prints it.
const std = @import("std");
const language = @import("compiler.zig");
const liveness = @import("qbe_liveness.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const values = @import("value_semantics.zig");

const Local = struct { index: u32, name: []const u8, role: []const u8, parent: ?u32 = null };
const Origin = struct { origin: []const u8, local: ?u32 = null, part: ?[]const u8 = null };
const Transfer = struct { pc: u32, kind: []const u8, target: ?u32 = null, source: Origin, class: []const u8 };
const Cow = struct { pc: u32, local: u32, via: u32, elements: bool, needed: bool, hoisted: ?u32 };
const ReturnOrigin = struct { kind: []const u8, params: []u16 };
const Function = struct {
    function: []const u8,
    return_origin: ReturnOrigin,
    borrow_origin: ReturnOrigin,
    locals: []Local,
    transfers: []Transfer,
    cow: []Cow,
    moves: []u32,
};

// spec-case: RETURN-BORROW-1
test "a returned element borrows only while its argument stays live and stable" {
    const previous = values.enabled();
    values.setEnabled(true);
    defer values.setEnabled(previous);
    const source =
        \\record Node:
        \\    data: bytes
        \\
        \\def at(nodes: list[Node], i: int) -> Node:
        \\    return nodes[i]
        \\
        \\def stable(nodes: list[Node]) -> int:
        \\    item = at(nodes, 0)
        \\    return len(item.data) + len(nodes)
        \\
        \\def changed(nodes: mut list[Node]) -> int:
        \\    item = at(nodes, 0)
        \\    nodes.append(Node(data=b"x"))
        \\    return len(item.data)
        \\
        \\def escaped(nodes: list[Node]) -> Node:
        \\    return at(nodes, 0)
        \\
        \\def main() -> int:
        \\    nodes = [Node(data=b"abc")]
        \\    return stable(nodes) + changed(mut nodes) + len(escaped(nodes).data)
    ;
    var stable = try explained(std.testing.allocator, source, "stable");
    defer stable.deinit();
    var changed = try explained(std.testing.allocator, source, "changed");
    defer changed.deinit();
    var escaped = try explained(std.testing.allocator, source, "escaped");
    defer escaped.deinit();
    try std.testing.expectEqualStrings("borrow", try classInto(stable.value, "assign", "item"));
    try std.testing.expectEqualStrings("copy", try classInto(changed.value, "assign", "item"));
    try std.testing.expectEqualStrings("copy", try classInto(escaped.value, "return", "nodes"));
}

/// The explanation of function `name` in `source`.
fn explained(a: std.mem.Allocator, source: []const u8, name: []const u8) !std.json.Parsed(Function) {
    var c = try language.Compilation.init(a, "ownership.my", source);
    defer c.deinit();
    const text = try c.explainOwnership(a);
    defer a.free(text);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        // The transfer assertions do not inspect additive copy-site detail.
        const parsed = try std.json.parseFromSlice(Function, a, line, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
        if (std.mem.eql(u8, parsed.value.function, name)) return parsed;
        parsed.deinit();
    }
    return error.TestUnexpectedResult;
}

/// The index of the local called `name`.
fn local(f: Function, name: []const u8) !u32 {
    for (f.locals) |item| if (std.mem.eql(u8, item.name, name)) return item.index;
    return error.TestUnexpectedResult;
}

/// The role of the local called `name`.
fn role(f: Function, name: []const u8) ![]const u8 {
    for (f.locals) |item| if (std.mem.eql(u8, item.name, name)) return item.role;
    return error.TestUnexpectedResult;
}

/// The class of the first transfer of `kind` into (or, for a return, out of)
/// the local called `name`.
fn classInto(f: Function, kind: []const u8, name: []const u8) ![]const u8 {
    const index = try local(f, name);
    for (f.transfers) |transfer| {
        if (!std.mem.eql(u8, transfer.kind, kind)) continue;
        const named = transfer.target orelse transfer.source.local orelse continue;
        if (named == index) return transfer.class;
    }
    return error.TestUnexpectedResult;
}

/// The copy-on-write sites that name local `name`.
fn sitesOf(f: Function, name: []const u8) !usize {
    const index = try local(f, name);
    var count: usize = 0;
    for (f.cow) |site| count += @intFromBool(site.local == index);
    return count;
}

/// The first copy-on-write site of local `name`.
fn siteOf(f: Function, name: []const u8) !Cow {
    const index = try local(f, name);
    for (f.cow) |site| if (site.local == index) return site;
    return error.TestUnexpectedResult;
}

// spec: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 an assignment moves, borrows or copies by what follows it" {
    const a = std.testing.allocator;
    var parsed = try explained(a,
        \\def main() -> int:
        \\    source = [1, 2, 3]
        \\    shared = source
        \\    total = len(shared) + len(source)
        \\    kept = [4, 5]
        \\    taken = kept
        \\    taken.append(6)
        \\    copied = [7]
        \\    other = copied
        \\    other.append(8)
        \\    return total + len(taken) + len(other) + len(copied)
    , "main");
    defer parsed.deinit();
    const f = parsed.value;
    // `source` is read after `shared` takes it, but neither is written: one value.
    try std.testing.expectEqualStrings("borrow", try classInto(f, "assign", "shared"));
    try std.testing.expectEqualStrings("borrowed", try role(f, "shared"));
    // `kept` is never read again: its value moves.
    try std.testing.expectEqualStrings("move", try classInto(f, "assign", "taken"));
    try std.testing.expectEqualStrings("owned", try role(f, "taken"));
    // `other` is written while `copied` is still read: a real copy.
    try std.testing.expectEqualStrings("copy", try classInto(f, "assign", "other"));
    // A fresh literal moves into its local.
    try std.testing.expectEqualStrings("move", try classInto(f, "assign", "source"));
}

// spec-case: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 a check a loop cannot invalidate moves to the loop entry" {
    const a = std.testing.allocator;
    var parsed = try explained(a,
        \\def fill(n: int) -> list[int]:
        \\    out: list[int] = []
        \\    for i in range(n):
        \\        out.append(i)
        \\    return out
        \\
        \\
        \\def main() -> int:
        \\    return len(fill(3))
    , "fill");
    defer parsed.deinit();
    const site = try siteOf(parsed.value, "out");
    try std.testing.expect(site.needed);
    try std.testing.expect(!site.elements);
    try std.testing.expect(site.hoisted != null);
    try std.testing.expectEqualStrings("move", try classInto(parsed.value, "return", "out"));
}

// spec-case: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 a list lent to a call inside the loop keeps its check in the loop" {
    const a = std.testing.allocator;
    var parsed = try explained(a,
        \\def keep(xs: list[int]) -> int:
        \\    return len(xs)
        \\
        \\
        \\def fill(n: int) -> int:
        \\    out: list[int] = []
        \\    total = 0
        \\    for i in range(n):
        \\        out.append(i)
        \\        total += keep(out)
        \\    return total
        \\
        \\
        \\def main() -> int:
        \\    return fill(3)
    , "fill");
    defer parsed.deinit();
    const site = try siteOf(parsed.value, "out");
    try std.testing.expect(site.needed);
    try std.testing.expect(site.hoisted == null);
    try std.testing.expectEqualStrings("borrow", try classInto(parsed.value, "argument", "out"));
}

// spec-case: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 a mut parameter is written without a check and an early return still moves" {
    const a = std.testing.allocator;
    var parsed = try explained(a,
        \\def push(xs: mut list[int], v: int) -> list[int]:
        \\    xs.append(v)
        \\    fresh = [v]
        \\    if v > 3:
        \\        return fresh
        \\    fresh.append(v)
        \\    return fresh
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    return len(push(mut values, 2))
    , "push");
    defer parsed.deinit();
    const site = try siteOf(parsed.value, "xs");
    try std.testing.expect(!site.needed);
    try std.testing.expectEqualStrings("mut_param", try role(parsed.value, "xs"));
    try std.testing.expectEqualStrings("move", try classInto(parsed.value, "return", "fresh"));
}

// spec-case: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 a match arm binding that is only read borrows the scrutinee" {
    const a = std.testing.allocator;
    var parsed = try explained(a,
        \\def size(value: Option[list[int]]) -> int:
        \\    match value:
        \\        case Some(items):
        \\            return len(items)
        \\        case None:
        \\            return 0
        \\
        \\
        \\def main() -> int:
        \\    return size(Some([1, 2]))
    , "size");
    defer parsed.deinit();
    try std.testing.expectEqualStrings("borrow", try classInto(parsed.value, "binding", "items"));
    try std.testing.expectEqualStrings("param", try role(parsed.value, "value"));
}

// spec-case: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 an element written through a temporary needs its elements unique" {
    const a = std.testing.allocator;
    var parsed = try explained(a,
        \\def build() -> int:
        \\    rows = [[1], [2]]
        \\    for i in range(2):
        \\        rows[i].append(i)
        \\    return len(rows[0])
        \\
        \\
        \\def main() -> int:
        \\    return build()
    , "build");
    defer parsed.deinit();
    const f = parsed.value;
    const rows = try local(f, "rows");
    var element_sites: usize = 0;
    for (f.cow) |site| element_sites += @intFromBool(site.local == rows and site.elements);
    try std.testing.expect(element_sites >= 1);
    try std.testing.expect(try sitesOf(f, "rows") >= 2);
}

// spec-case: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 classes, callbacks and arenas are answered, never refused" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    const a = std.testing.allocator;
    const source =
        \\class Node:
        \\    value: int
        \\    children: list[int]
        \\
        \\
        \\def count(node: Node) -> int:
        \\    kids = node.children
        \\    return len(kids)
        \\
        \\
        \\def apply(f: def(list[int]) -> int effects(), xs: list[int]) -> int:
        \\    return f(xs)
        \\
        \\
        \\def scoped() -> int:
        \\    with arena():
        \\        xs = [1, 2, 3]
        \\        ys = xs
        \\        n = len(ys) + len(xs)
        \\    return n
        \\
        \\
        \\def length(xs: list[int]) -> int effects():
        \\    return len(xs)
        \\
        \\
        \\def main() -> int:
        \\    node = Node(value=1, children=[1, 2])
        \\    return count(node) + apply(length, [1]) + scoped()
    ;
    var node = try explained(a, source, "count");
    defer node.deinit();
    try std.testing.expectEqualStrings("borrow", try classInto(node.value, "assign", "kids"));
    var callback = try explained(a, source, "apply");
    defer callback.deinit();
    try std.testing.expectEqualStrings("param", try role(callback.value, "xs"));
    var scoped = try explained(a, source, "scoped");
    defer scoped.deinit();
    try std.testing.expectEqualStrings("borrow", try classInto(scoped.value, "assign", "ys"));
}

// spec-case: OWNERSHIP-ANALYSIS-1
test "OWNERSHIP-ANALYSIS-1 the shared liveness solution fails cleanly without memory" {
    // The second allocation fails, after the live-in rows exist: the solver
    // releases them and reports the failure.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const code = [_]bytecode.Instruction{.{ .span = .{ .start = 0, .end = 0 }, .op = .ret }};
    const locals = [_]typed.Local{.{ .name = "x", .declaration = .{ .start = 0, .end = 0 }, .ty = .i64, .mutable = false }};
    const function: bytecode.Function = .{ .scope = .{ .locals = &locals, .instructions = &code }, .id = @fromBackingInt(0), .name = "f" };
    const states = [_]?[]const typed.Type{&.{}};
    try std.testing.expectError(error.OutOfMemory, liveness.solve(failing.allocator(), .{ .function = function, .states = &states, .pinned = &.{false} }));
}

// spec: MUT-REBIND-CALLER-1
test "MUT-REBIND-CALLER-1 a rebound mut parameter keeps its caller-storage role and requires checks" {
    var parsed = try explained(std.testing.allocator,
        \\def replaced(xs: mut list[int], other: list[int]) -> list[int]:
        \\    xs = other
        \\    xs.append(7)
        \\    return xs
        \\def main() -> int:
        \\    values = [1]
        \\    return len(replaced(mut values, [2]))
    , "replaced");
    defer parsed.deinit();
    try std.testing.expect((try siteOf(parsed.value, "xs")).needed);
    try std.testing.expectEqualStrings("mut_param", try role(parsed.value, "xs"));
}

// spec-case: MUT-REBIND-CALLER-1
test "MUT-REBIND-CALLER-1 a conditional parameter replacement checks its captured receiver" {
    var parsed = try explained(std.testing.allocator,
        \\def replaced(xs: mut list[int], other: list[int], choose: bool) -> list[int]:
        \\    if choose:
        \\        xs = other
        \\    xs[0] = 7
        \\    return xs
        \\def main() -> int:
        \\    values = [1]
        \\    return len(replaced(mut values, [2], True))
    , "replaced");
    defer parsed.deinit();
    try std.testing.expect((try siteOf(parsed.value, "xs")).needed);
    try std.testing.expectEqualStrings("mut_param", try role(parsed.value, "xs"));
}

// spec-case: D2-VIEW-STORAGE-1
test "explicit view snapshot keeps a separate mapping copy" {
    const source =
        \\record Envelope:
        \\    live: list[int]
        \\
        \\def main() -> int:
        \\    mapping = {1: 7}
        \\    owner = Envelope(list(mapping.values()))
        \\    snapshot = mapping
        \\    snapshot[1] = 11
        \\    return mapping[1] + snapshot[1]
    ;
    var parsed = try explained(std.testing.allocator, source, "main");
    defer parsed.deinit();
    try std.testing.expectEqualStrings("copy", try classInto(parsed.value, "assign", "snapshot"));
}

// spec: OWNERSHIP-FIELD-WRITE-1
test "record field writes invalidate a saved record borrow" {
    var direct = try explained(std.testing.allocator,
        \\record State:
        \\    values: list[int]
        \\def main() -> int:
        \\    with arena():
        \\        state = State([12])
        \\        saved = state
        \\        state.values.append(14)
        \\        return len(saved.values) + len(state.values)
    , "main");
    defer direct.deinit();
    var nested = try explained(std.testing.allocator,
        \\record State:
        \\    values: list[int]
        \\record Outer:
        \\    state: State
        \\def push(values: mut list[int]):
        \\    values.append(14)
        \\def main() -> int:
        \\    state = Outer(State([12]))
        \\    saved = state
        \\    push(mut state.state.values)
        \\    return len(saved.state.values) + len(state.state.values)
    , "main");
    defer nested.deinit();
    try std.testing.expectEqualStrings("copy", try classInto(direct.value, "assign", "saved"));
    try std.testing.expectEqualStrings("owned", try role(direct.value, "saved"));
    try std.testing.expectEqualStrings("copy", try classInto(nested.value, "assign", "saved"));
}

// spec: OWNERSHIP-MUT-RECORD-WRITE-1
test "a mut record argument invalidates a saved borrow of the record or its field" {
    var whole = try explained(std.testing.allocator,
        \\record Output:
        \\    buffer: list[int]
        \\def append(out: mut Output, value: int):
        \\    out.buffer.append(value)
        \\def main() -> int:
        \\    o = Output([1])
        \\    before = o
        \\    append(mut o, 2)
        \\    return len(before.buffer) * 10 + len(o.buffer)
    , "main");
    defer whole.deinit();
    var field = try explained(std.testing.allocator,
        \\record Output:
        \\    buffer: list[int]
        \\def append(out: mut Output, value: int):
        \\    out.buffer.append(value)
        \\def main() -> int:
        \\    o = Output([1])
        \\    before = o.buffer
        \\    append(mut o, 2)
        \\    return len(before) * 10 + len(o.buffer)
    , "main");
    defer field.deinit();
    try std.testing.expectEqualStrings("copy", try classInto(whole.value, "assign", "before"));
    try std.testing.expectEqualStrings("owned", try role(whole.value, "before"));
    try std.testing.expectEqualStrings("copy", try classInto(field.value, "assign", "before"));
    try std.testing.expectEqualStrings("owned", try role(field.value, "before"));
}

// spec: OWNERSHIP-MUT-RECORD-WRITE-2
test "a borrow read only for a scalar between a mut record reference and its call stays a borrow" {
    const source =
        \\record Box:
        \\    tag: int
        \\    names: list[int]
        \\record State:
        \\    boxes: list[Box]
        \\union Slot:
        \\    empty,
        \\    full: Box
        \\record Store:
        \\    slots: list[Slot]
        \\def grow(state: mut State, tag: int):
        \\    state.boxes.append(Box(tag, [tag]))
        \\def fill(store: mut Store, tag: int):
        \\    store.slots.append(Slot.full(Box(tag, [tag])))
        \\def scalar(state: mut State) -> int:
        \\    box = state.boxes[0]
        \\    grow(mut state, box.tag)
        \\    return len(state.boxes)
        \\def bound(store: mut Store) -> int:
        \\    match store.slots[0]:
        \\        case Slot.full(box):
        \\            fill(mut store, box.tag)
        \\            return len(store.slots)
        \\        case Slot.empty:
        \\            return 0
        \\def main() -> int:
        \\    state = State([Box(1, [1])])
        \\    store = Store([Slot.full(Box(2, [2]))])
        \\    return scalar(mut state) + bound(mut store)
    ;
    var scalar = try explained(std.testing.allocator, source, "scalar");
    defer scalar.deinit();
    var bound = try explained(std.testing.allocator, source, "bound");
    defer bound.deinit();
    try std.testing.expectEqualStrings("borrow", try classInto(scalar.value, "assign", "box"));
    try std.testing.expectEqualStrings("borrowed", try role(scalar.value, "box"));
    try std.testing.expectEqualStrings("borrow", try classInto(bound.value, "binding", "box"));
}

// spec-case: OWNERSHIP-MUT-RECORD-WRITE-2
test "a borrow a mut record call may still observe keeps its copy" {
    const source =
        \\record Box:
        \\    tag: int
        \\    names: list[int]
        \\record State:
        \\    boxes: list[Box]
        \\def grow(state: mut State, tag: int):
        \\    state.boxes[0].names.append(tag)
        \\def keep(state: mut State, names: list[int]) -> int:
        \\    state.boxes[0].names.append(7)
        \\    return len(names)
        \\def hold(state: mut State, box: Box) -> int:
        \\    state.boxes[0].names.append(7)
        \\    return len(box.names)
        \\def after(state: mut State) -> int:
        \\    box = state.boxes[0]
        \\    grow(mut state, box.tag)
        \\    return len(box.names)
        \\def field(state: mut State) -> int:
        \\    box = state.boxes[0]
        \\    return keep(mut state, box.names)
        \\def whole(state: mut State) -> int:
        \\    box = state.boxes[0]
        \\    return hold(mut state, box)
        \\def nested(state: mut State) -> int:
        \\    box = state.boxes[0]
        \\    return keep(mut state, [box.tag, len(box.names)])
        \\def first(names: list[int], state: mut State) -> int:
        \\    state.boxes[0].names.append(7)
        \\    return len(names)
        \\def early(state: mut State) -> int:
        \\    box = state.boxes[0]
        \\    return first(box.names, mut state)
        \\def main() -> int:
        \\    state = State([Box(1, [1])])
        \\    return after(mut state) + field(mut state) + whole(mut state) + nested(mut state) + early(mut state)
    ;
    var after = try explained(std.testing.allocator, source, "after");
    defer after.deinit();
    var field = try explained(std.testing.allocator, source, "field");
    defer field.deinit();
    var whole = try explained(std.testing.allocator, source, "whole");
    defer whole.deinit();
    var nested = try explained(std.testing.allocator, source, "nested");
    defer nested.deinit();
    var early = try explained(std.testing.allocator, source, "early");
    defer early.deinit();
    try std.testing.expectEqualStrings("copy", try classInto(after.value, "assign", "box"));
    try std.testing.expectEqualStrings("copy", try classInto(field.value, "assign", "box"));
    try std.testing.expectEqualStrings("copy", try classInto(whole.value, "assign", "box"));
    try std.testing.expectEqualStrings("copy", try classInto(nested.value, "assign", "box"));
    try std.testing.expectEqualStrings("copy", try classInto(early.value, "assign", "box"));
}

// spec-case: OWNERSHIP-FIELD-WRITE-1
test "record field reads and writes to independent named homes preserve borrows" {
    var parsed = try explained(std.testing.allocator,
        \\record State:
        \\    values: list[int]
        \\def main() -> int:
        \\    state = State([12])
        \\    saved = state
        \\    copied = state.values
        \\    copied.append(14)
        \\    return len(saved.values) + len(state.values) + len(copied)
    , "main");
    defer parsed.deinit();
    try std.testing.expectEqualStrings("borrow", try classInto(parsed.value, "assign", "saved"));
    try std.testing.expectEqualStrings("copy", try classInto(parsed.value, "assign", "copied"));
    try std.testing.expectEqualStrings("borrowed", try role(parsed.value, "saved"));
}

// spec-case: OWNERSHIP-FIELD-WRITE-1
test "unknown temporary write ancestry cannot justify a borrow" {
    try std.testing.expect(uncertainFieldWrite(std.testing.allocator, 2, .{ .origin = .local, .local = 0 }, true));
    try std.testing.expect(uncertainFieldWrite(std.testing.allocator, 1, .{}, true));
    try std.testing.expect(uncertainFieldWrite(std.testing.allocator, 1, .{ .origin = .local, .local = 1 }, true));
    try std.testing.expect(!uncertainFieldWrite(std.testing.allocator, 1, .{ .origin = .fresh }, true));
    try std.testing.expect(!uncertainFieldWrite(std.testing.allocator, 1, .{ .origin = .local, .local = 0 }, false));
}

fn uncertainFieldWrite(a: std.mem.Allocator, count: u32, source: @import("ownership_model.zig").Source, temporary: bool) bool {
    const model = @import("ownership_model.zig");
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const locals = [_]typed.Local{
        .{ .name = "root", .declaration = span, .ty = .i64, .mutable = true },
        .{ .name = if (temporary) "<receiver>" else "copied", .declaration = span, .ty = .i64, .mutable = true },
    };
    const code = [_]bytecode.Instruction{
        .{ .span = span, .op = .{ .store_local = @fromBackingInt(1) } },
        .{ .span = span, .op = .{ .buffer_operation = .{ .kind = .append, .owner = @fromBackingInt(1), .output = .unit } } },
    };
    var flags = [_]bool{ false, false };
    var roles = [_]model.Role{ .owned, .owned };
    var parents = [_]u32{ model.none, model.none };
    var counts = [_]u32{ 0, count };
    var pcs = [_]u32{ model.none, 0 };
    const stack = [_]model.Source{source};
    const flow = [_]?[]const model.Source{ &stack, &.{} };
    const context: model.Context = .{
        .allocator = a,
        .code = .{ .program = .{ .functions = &.{} }, .function = .{ .scope = .{ .instructions = &code, .locals = &locals }, .id = @fromBackingInt(0), .name = "probe" }, .states = &.{} },
        .live = .{ .words = 0, .live_in = &.{}, .live_out = &.{} },
        .flow = .{ .at = &flow, .pops = &.{}, .targets = &.{} },
        .locals = .{ .list = &locals, .params = 0, .value = &flags, .managed = &flags, .roles = &roles, .parents = &parents, .step = &flags },
        .defs = .{ .count = &counts, .pc = &pcs, .mutated = &flags },
        .marks = .{ .unique_load = &flags, .path_read = &flags, .suppressed = &flags, .plain_read = &flags },
    };
    return context.writesTree(1, 0, null);
}

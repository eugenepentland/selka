//! RC-READONLY-ANCHOR-1: values read out of read-only parameters take no token.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const interval =
    \\union Value:
    \\    nil,
    \\    number: float
    \\record Frame:
    \\    code: list[int]
    \\    ip: int
    \\record Runtime:
    \\    stack: list[Value]
    \\    top: int
    \\def next(frame: mut Frame) -> int:
    \\    frame.ip = frame.ip + 1
    \\    return frame.code[frame.ip - 1]
    \\def fetch(rt: mut Runtime, frame: mut Frame) -> Value:
    \\    rt.top = rt.top + 1
    \\    return rt.stack[next(mut frame)]
    \\def shrink(rt: mut Runtime) -> int:
    \\    rt.stack = [Value.nil]
    \\    return 0
    \\def replaced(rt: mut Runtime) -> Value:
    \\    return rt.stack[shrink(mut rt)]
    \\def main() -> int:
    \\    rt = Runtime([Value.nil, Value.number(1.0)], 0)
    \\    frame = Frame([1, 0], 0)
    \\    first = fetch(mut rt, mut frame)
    \\    second = replaced(mut rt)
    \\    return rt.top + len(rt.stack)
;
const operand =
    \\record Table:
    \\    entries: list[int]
    \\record Runtime:
    \\    globals: Table
    \\    names: list[str]
    \\    top: int
    \\def lookup(t: Table, at: int) -> int:
    \\    return t.entries[at]
    \\def hash_of(rt: Runtime, at: int) -> int:
    \\    return len(rt.names[at])
    \\def global(rt: mut Runtime, at: int) -> int:
    \\    rt.top = rt.top + 1
    \\    return lookup(rt.globals, hash_of(rt, at))
    \\def reset(rt: mut Runtime) -> int:
    \\    rt.globals = Table([5])
    \\    return 0
    \\def reset_global(rt: mut Runtime) -> int:
    \\    return lookup(rt.globals, reset(mut rt))
    \\def main() -> int:
    \\    rt = Runtime(Table([1, 2]), ["a", "b"], 0)
    \\    return global(mut rt, 1) + reset_global(mut rt)
;
const accessor =
    \\record Text:
    \\    chars: bytes
    \\    hash: u32
    \\union Obj:
    \\    free,
    \\    text: Text
    \\record Runtime:
    \\    objects: list[Obj]
    \\def text_obj(rt: Runtime, at: int) -> Text:
    \\    match rt.objects[at]:
    \\        case Obj.text(payload):
    \\            return payload
    \\        case _:
    \\            return Text(chars=b"", hash=0u32)
    \\def text_hash(rt: Runtime, at: int) -> u32:
    \\    return text_obj(rt, at).hash
    \\def kept(rt: Runtime, at: int) -> Text:
    \\    found = text_obj(rt, at)
    \\    return found
    \\def main() -> int:
    \\    rt = Runtime([Obj.text(Text(b"a" + b"b", 3u32))])
    \\    return int(text_hash(rt, 0)) + len(kept(rt, 0).chars)
;
const source =
    \\record Chunk:
    \\    code: list[int]
    \\record Function:
    \\    arity: int
    \\    chunk: Chunk
    \\union Obj:
    \\    free,
    \\    function: Function
    \\record Runtime:
    \\    objects: list[Obj]
    \\    count: int
    \\def arity(rt: Runtime, at: int) -> int:
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.arity + len(payload.chunk.code)
    \\        case _:
    \\            return -1
    \\def code(rt: Runtime, at: int) -> list[int]:
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.chunk.code
    \\        case _:
    \\            return []
    \\def mutated(rt: mut Runtime, at: int) -> int:
    \\    rt.count = at
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.arity
    \\        case _:
    \\            return -1
    \\def main() -> int:
    \\    rt = Runtime([Obj.function(Function(2, Chunk([7])))], 1)
    \\    return arity(rt, 0) + len(code(rt, 0)) + mutated(mut rt, 0)
;

const aliases =
    \\record Frame:
    \\    rows: list[list[int]]
    \\    n: int
    \\record Other:
    \\    rows: list[list[int]]
    \\    n: int
    \\def reset(other: mut Frame) -> int:
    \\    other.rows = [[7]]
    \\    return 0
    \\def reset_other(other: mut Other) -> int:
    \\    other.rows = [[7]]
    \\    return 0
    \\def count(rows: list[list[int]], k: int) -> int:
    \\    return len(rows) + k
    \\def interval(frame: mut Frame, other: mut Frame) -> int:
    \\    frame.n = frame.n + 1
    \\    return len(frame.rows[reset(mut other)])
    \\def distinct_interval(frame: mut Frame, other: mut Other) -> int:
    \\    frame.n = frame.n + 1
    \\    return len(frame.rows[reset_other(mut other)])
    \\def operand(frame: mut Frame, other: mut Frame) -> int:
    \\    frame.n = frame.n + 1
    \\    return count(frame.rows, reset(mut other))
    \\def distinct_operand(frame: mut Frame, other: mut Other) -> int:
    \\    frame.n = frame.n + 1
    \\    return count(frame.rows, reset_other(mut other))
    \\def main() -> int:
    \\    frame = Frame([[1, 2], [3]], 0)
    \\    second = Frame([[4]], 0)
    \\    other = Other([[1]], 0)
    \\    total = interval(mut frame, mut second) + operand(mut frame, mut second)
    \\    return total + distinct_interval(mut frame, mut other) + distinct_operand(mut frame, mut other)
;

fn operations(name: []const u8) !usize {
    return operationsIn(source, name);
}

fn operationsIn(program: []const u8, name: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_readonly_anchor.my", program);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        const il = function.il;
        return std.mem.count(u8, il, "# RC-GLUE-1 loan") + std.mem.count(u8, il, "# RC-GLUE-1 retain");
    }
    return error.TestUnexpectedResult;
}

// spec: RC-READONLY-ANCHOR-1
test "RC reads out of a read-only parameter take no loan or payload retain" {
    try t.expectEqual(@as(usize, 0), try operations("arity"));
}

// spec-case: RC-READONLY-ANCHOR-1
test "RC anchored reads still copy into returned owners and mut roots keep tokens" {
    try t.expect(try operations("code") > 0);
    try t.expect(try operations("mutated") > 0);
}

// spec: RC-INTERVAL-ANCHOR-1
test "RC list temporaries of a mut record root borrow across calls that do not receive it" {
    try t.expectEqual(@as(usize, 0), try operationsIn(interval, "fetch"));
}

// spec-case: RC-INTERVAL-ANCHOR-1
test "RC list temporaries keep their loan across a call that receives the root" {
    try t.expect(try operationsIn(interval, "replaced") > 0);
}

// spec-case: RC-INTERVAL-ANCHOR-1
test "RC interval anchors cover every list temporary of a long function" {
    var text: std.Io.Writer.Allocating = .init(t.allocator);
    defer text.deinit();
    const w = &text.writer;
    try w.writeAll("union Value:\n    nil,\n    number: float\nrecord Frame:\n    code: list[int]\n    ip: int\nrecord Runtime:\n    stack: list[Value]\n    top: int\n");
    try w.writeAll("def next(frame: mut Frame) -> int:\n    frame.ip = frame.ip + 1\n    return frame.code[0]\n");
    try w.writeAll("def long(rt: mut Runtime, frame: mut Frame) -> int:\n    rt.top = 0\n    total = 0\n");
    for (0..40) |_| try w.writeAll("    match rt.stack[next(mut frame)]:\n        case Value.nil:\n            total += 1\n        case _:\n            total += 2\n");
    try w.writeAll("    return total\n");
    try w.writeAll("def main() -> int:\n    rt = Runtime([Value.nil], 0)\n    frame = Frame([0], 0)\n    return long(mut rt, mut frame)\n");
    try t.expectEqual(@as(usize, 0), try operationsIn(text.written(), "long"));
}

// spec: RC-OPERAND-ANCHOR-1
test "RC field reads of a mut root passed straight to a call take no loan" {
    try t.expectEqual(@as(usize, 0), try operationsIn(operand, "global"));
}

// spec-case: RC-OPERAND-ANCHOR-1
test "RC field reads keep their loan when the root is passed mut before the call" {
    try t.expect(try operationsIn(operand, "reset_global") > 0);
}

// spec-case: RC-BORROW-MATCH-1
test "RC borrowed match accessor results read in place take no owner" {
    try t.expectEqual(@as(usize, 0), try operationsIn(accessor, "text_hash"));
    try t.expect(try operationsIn(accessor, "kept") > 0);
}

// spec-case: RC-INTERVAL-ANCHOR-1
test "RC list temporaries of a mut root borrow while their counted elements take loans" {
    const counted =
        \\record Runtime:
        \\    names: list[str]
        \\    top: int
        \\def name(rt: mut Runtime, at: int) -> int:
        \\    rt.top = rt.top + 1
        \\    return len(rt.names[at])
        \\def main() -> int:
        \\    rt = Runtime(["a", "bc"], 0)
        \\    return name(mut rt, 1)
    ;
    try t.expectEqual(@as(usize, 1), try operationsIn(counted, "name"));
}

// spec-case: RC-OPERAND-ANCHOR-1
test "RC field reads of a mut root consumed by a call whose result is matched take no loan" {
    const matched =
        \\record Table:
        \\    entries: list[int]
        \\record Runtime:
        \\    globals: Table
        \\    names: list[str]
        \\    top: int
        \\def find(t: Table, at: int) -> Option[int]:
        \\    if at < len(t.entries):
        \\        return Some(t.entries[at])
        \\    return None
        \\def hash_of(rt: Runtime, at: int) -> int:
        \\    return len(rt.names[at])
        \\def global(rt: mut Runtime, at: int) -> int:
        \\    rt.top = rt.top + 1
        \\    match find(rt.globals, hash_of(rt, at)):
        \\        case Some(found):
        \\            return found
        \\        case None:
        \\            return -1
        \\def main() -> int:
        \\    rt = Runtime(Table([1, 2]), ["a", "b"], 0)
        \\    return global(mut rt, 1)
    ;
    try t.expectEqual(@as(usize, 0), try operationsIn(matched, "global"));
}

// spec-case: RC-READONLY-ANCHOR-1
test "RC records copied out of a read-only list into a named local take no token" {
    const records =
        \\record Span:
        \\    source: bytes
        \\    start: int
        \\record Pin:
        \\    part: int
        \\    net: Span
        \\    nc: bool
        \\def count(pins: list[Pin], wanted: int) -> int:
        \\    total = 0
        \\    j = 0
        \\    while j < len(pins):
        \\        other = pins[j]
        \\        if j % 2 == 0:
        \\            other = pins[0]
        \\        if not other.nc and other.part == wanted:
        \\            total += other.net.start
        \\        j += 1
        \\    return total
        \\def main() -> int:
        \\    return count([Pin(1, Span(b"a" + b"b", 2), False)], 1)
    ;
    try t.expectEqual(@as(usize, 0), try operationsIn(records, "count"));
}

const range_keys =
    \\def frequencies(seq: str, k: int) -> dict[str, int]:
    \\    counts: dict[str, int] = {}
    \\    for i in range(len(seq) - k + 1):
    \\        key = seq[i:i + k]
    \\        counts[key] = counts.get(key, 0) + 1
    \\    return counts
    \\def rebound(seq: str, k: int) -> dict[str, int]:
    \\    counts: dict[str, int] = {}
    \\    for i in range(len(seq) - k + 1):
    \\        key = seq[i:i + k]
    \\        counts[key] = counts.get(key, 0) + 1
    \\        seq = seq + "A"
    \\    return counts
    \\def main() -> int:
    \\    return len(frequencies("GATTACA", 2)) + len(rebound("GATTACA", 2))
;

// spec: RC-ANCHORED-RANGE-KEY-1
test "RC range keys sliced from a never-written read-only parameter take no loan or retain" {
    // The one retain left is the returned dictionary's take-or-copy.
    try t.expectEqual(@as(usize, 1), try operationsIn(range_keys, "frequencies"));
    try t.expect(try operationsIn(range_keys, "rebound") > 1);
}

// spec: RC-OPERAND-ANCHOR-2
test "RC length reads of a mut record's field take no loan" {
    const lengths =
        \\record Output:
        \\    buffer: byte_buffer
        \\    items: list[str]
        \\    failed: bool
        \\def full(out: mut Output, limit: int) -> bool:
        \\    if len(out.buffer) > limit or len(out.items) > limit:
        \\        out.failed = True
        \\    return out.failed
        \\def kept(out: mut Output, limit: int) -> int:
        \\    items = out.items
        \\    out.items = ["b"]
        \\    return len(items) + limit
        \\def main() -> int:
        \\    values: list[int] = []
        \\    out = Output(byte_buffer(values), ["a"], False)
        \\    if full(mut out, 3):
        \\        return 1
        \\    return kept(mut out, 3)
    ;
    try t.expectEqual(@as(usize, 0), try operationsIn(lengths, "full"));
    // A named copy that outlives a write of the record keeps its owner.
    try t.expect(try operationsIn(lengths, "kept") > 0);
}

const intervals =
    \\record Span:
    \\    source: bytes
    \\    start: int
    \\    end: int
    \\record Pin:
    \\    part: int
    \\    net: Span
    \\    display: Span
    \\    net_id: int
    \\def equal(a: Span, b: Span) -> bool:
    \\    if a.end - a.start != b.end - b.start:
    \\        return False
    \\    i = 0
    \\    while i < a.end - a.start:
    \\        if a.source[a.start + i] != b.source[b.start + i]:
    \\            return False
    \\        i += 1
    \\    return True
    \\def normalize(pins: mut list[Pin]):
    \\    i = 0
    \\    while i < len(pins):
    \\        raw_id = -1
    \\        j = 0
    \\        while j < i:
    \\            if raw_id < 0 and equal(pins[j].net, pins[i].net):
    \\                raw_id = pins[j].net_id
    \\            j += 1
    \\        if raw_id < 0:
    \\            raw_id = i
    \\        pins[i].net_id = raw_id
    \\        i += 1
    \\def collect(count: int) -> int:
    \\    out: list[Pin] = []
    \\    k = 0
    \\    while k < count:
    \\        j = 0
    \\        found = False
    \\        while j < len(out):
    \\            previous = out[j]
    \\            if previous.part == k % 3:
    \\                found = True
    \\            j += 1
    \\        if not found:
    \\            out.append(Pin(k % 3, Span(b"ab" + b"c", 0, 3), Span(b"d", 0, 1), k))
    \\        k += 1
    \\    return len(out)
    \\def stale(pins: mut list[Pin]) -> int:
    \\    first = pins[0]
    \\    pins[0].net = Span(b"xy" + b"z", 0, 3)
    \\    return first.net.end + first.part
    \\def main() -> int:
    \\    pins = [Pin(0, Span(b"a" + b"b", 0, 2), Span(b"c", 0, 1), 0), Pin(1, Span(b"ab", 0, 2), Span(b"c", 0, 1), 0)]
    \\    normalize(mut pins)
    \\    return pins[1].net_id + collect(5) + stale(mut pins)
;

fn markersIn(program: []const u8, name: []const u8, marker: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_interval_anchor.my", program);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| if (std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, marker);
    return error.TestUnexpectedResult;
}

// spec: RC-INTERVAL-ANCHOR-2
test "RC reads out of a mut or local list that nothing writes meanwhile take no token" {
    // The inlined `equal` parameters and the element local are bound in place.
    try t.expectEqual(@as(usize, 2), try markersIn(intervals, "normalize", "# RC-READONLY-ANCHOR-1 local"));
    try t.expectEqual(@as(usize, 1), try markersIn(intervals, "collect", "# RC-READONLY-ANCHOR-1 local"));
}

// spec-case: RC-INTERVAL-ANCHOR-2
test "RC a value read out of a list that is written while it is live keeps its token" {
    try t.expectEqual(@as(usize, 0), try markersIn(intervals, "stale", "# RC-READONLY-ANCHOR-1 local"));
    try t.expect(try operationsIn(intervals, "stale") > 0);
}

const calls =
    \\record Span:
    \\    source: bytes
    \\    end: int
    \\record Pin:
    \\    part: int
    \\    net: Span
    \\def pick(pins: list[Pin], part: int) -> Pin:
    \\    i = 0
    \\    while i < len(pins):
    \\        if pins[i].part == part:
    \\            return pins[i]
    \\        i += 1
    \\    return pins[0]
    \\def count(pins: list[Pin], parts: int) -> list[int]:
    \\    out: list[int] = []
    \\    j = 0
    \\    while j < parts:
    \\        found = pick(pins, j)
    \\        out.append(found.net.end + found.part)
    \\        j += 1
    \\    return out
    \\def local_pick(parts: int) -> int:
    \\    pins = [Pin(0, Span(b"a" + b"b", 2)), Pin(1, Span(b"c", 1))]
    \\    found = pick(pins, parts)
    \\    pins[0] = Pin(5, Span(b"d", 1))
    \\    return found.net.end + pins[0].part
    \\def main() -> int:
    \\    pins = [Pin(0, Span(b"a" + b"b", 2)), Pin(1, Span(b"c", 1))]
    \\    return len(count(pins, 2)) + local_pick(1)
;

// spec: RC-BORROW-CALL-ANCHOR-1
test "RC a local filled by a borrowed call out of a read-only parameter takes no owner" {
    try t.expectEqual(@as(usize, 1), try markersIn(calls, "count", "# RC-READONLY-ANCHOR-1 local"));
}

// spec-case: RC-BORROW-CALL-ANCHOR-1
test "RC a borrowed call out of a local list keeps its owner" {
    try t.expectEqual(@as(usize, 0), try markersIn(calls, "local_pick", "# RC-READONLY-ANCHOR-1 local"));
}

const carried =
    \\record Span:
    \\    source: bytes
    \\    start: int
    \\    end: int
    \\record Pin:
    \\    part: int
    \\    net: Span
    \\def equal(a: Span, b: Span) -> bool:
    \\    if a.end - a.start != b.end - b.start:
    \\        return False
    \\    i = 0
    \\    while i < a.end - a.start:
    \\        if a.source[a.start + i] != b.source[b.start + i]:
    \\            return False
    \\        i += 1
    \\    return True
    \\def matches(pins: list[Pin], net: Span) -> list[int]:
    \\    base = net
    \\    base.end = net.end - 1
    \\    out: list[int] = []
    \\    i = 0
    \\    while i < len(pins):
    \\        pin = pins[i]
    \\        if equal(pin.net, base):
    \\            out.append(pin.part)
    \\        i += 1
    \\    return out
    \\def main() -> int:
    \\    pins = [Pin(0, Span(b"a" + b"b", 0, 1)), Pin(1, Span(b"ab", 0, 2))]
    \\    return len(matches(pins, Span(b"ab", 0, 2)))
;

// spec: RC-READONLY-ANCHOR-2
test "RC an inlined call's first argument read out of an anchored local is bound in place" {
    // `pin` (the element) and the inlined `a` (its field) are bound; `b` is
    // filled from the owned local `base` and keeps its copy.
    try t.expectEqual(@as(usize, 1), try markersIn(carried, "matches", "# RC-READONLY-ANCHOR-1 local"));
    try t.expectEqual(@as(usize, 1), try markersIn(carried, "matches", "# RC-ELEMENT-BORROW-3 local"));
}

// MUT-EXCLUSIVE-1 rejects `interval(mut frame, mut frame)`, so these refusals
// are defense in depth: the callee's parameter types alone decide them.
// spec: RC-INTERVAL-ANCHOR-3
test "RC mut record roots another mut parameter of their type may name keep their loans" {
    try t.expect(try operationsIn(aliases, "interval") > try operationsIn(aliases, "distinct_interval"));
    try t.expect(try operationsIn(aliases, "operand") > try operationsIn(aliases, "distinct_operand"));
}

const list_aliases =
    \\record Span:
    \\    source: bytes
    \\    end: int
    \\record Pin:
    \\    part: int
    \\    net: Span
    \\def aliased(pins: mut list[Pin], other: mut list[Pin]) -> int:
    \\    pins.append(Pin(9, Span(b"x", 1)))
    \\    first = pins[0]
    \\    other[0] = Pin(1, Span(b"q", 1))
    \\    return first.part + len(first.net.source)
    \\def distinct(pins: mut list[Pin], other: mut list[int]) -> int:
    \\    pins.append(Pin(9, Span(b"x", 1)))
    \\    first = pins[0]
    \\    other[0] = 1
    \\    return first.part + len(first.net.source)
    \\def main() -> int:
    \\    a = [Pin(3, Span(b"ab", 2))]
    \\    b = [Pin(4, Span(b"c", 1))]
    \\    c = [0]
    \\    d = [Pin(5, Span(b"d", 1))]
    \\    return aliased(mut a, mut d) + distinct(mut b, mut c)
;

// spec: RC-INTERVAL-ANCHOR-4
test "RC a mut list another mut parameter of its type may name anchors nothing" {
    try t.expectEqual(@as(usize, 0), try markersIn(list_aliases, "aliased", "# RC-READONLY-ANCHOR-1 local"));
    try t.expect(try markersIn(list_aliases, "distinct", "# RC-READONLY-ANCHOR-1 local") > 0);
    try t.expect(try operationsIn(list_aliases, "aliased") > try operationsIn(list_aliases, "distinct"));
}

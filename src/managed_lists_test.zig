//! Source-level managed aliases, native rooting, effects, and storage boundaries.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(text: []const u8) !native.Run {
    var compilation = try language.Compilation.init(t.allocator, "managed.my", text);
    defer compilation.deinit();
    return native.runWithOptions(&compilation, .{ .gc_stress = true }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
}

fn firstError(items: []const language.diagnostic.Diagnostic) ?language.diagnostic.Diagnostic {
    for (items) |item| if (item.severity == .err) return item;
    return null;
}

fn reject(text: []const u8, expected: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-managed.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diag = firstError(compilation.diagnostics.items) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings(expected, diag.code);
}

fn rejectAll(sources: []const []const u8, code: []const u8) !void {
    for (sources) |source| try reject(source, code);
}

// spec: GC-SOURCE-9
test "bytecode rejects managed metadata on a shape that cannot own storage" {
    var compilation = try language.Compilation.init(t.allocator, "forged-managed.my",
        \\record Record:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.emit();
    var program = compilation.code.?;
    const records = try t.allocator.dupe(@import("typed.zig").Record, program.records);
    defer t.allocator.free(records);
    // A managed nominal record is legal now that `class` is a managed reference;
    // an array or variant is not a record and cannot own managed storage.
    records[0].managed = true;
    records[0].shape = .{ .array = .{ .element = .i64, .length = 2 } };
    program.records = records;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
}

// spec: GC-SOURCE-1
test "managed aliases mutate immutable bindings across helpers without allocator authority" {
    const source =
        \\def change(values: list[i64]):
        \\    values.append(40)
        \\    values[0u64] = 42
        \\
        \\
        \\def main() -> i64:
        \\    values: list[i64] = []
        \\    alias = values
        \\    change(alias)
        \\    if len(values) != 1:
        \\        return 1
        \\    return values[0u64]
    ;
    const result = try execute(source);
    try t.expectEqual(@as(i64, 42), result.value);
}

// spec: GC-SOURCE-2
test "managed recursive record cycles are traced at a later managed allocation" {
    const source =
        \\class Node:
        \\    children: list[Node]
        \\    value: i64
        \\
        \\
        \\def cycle():
        \\    nodes: list[Node] = []
        \\    nodes.append(Node(children=nodes, value=42))
        \\    node = nodes[0u64]
        \\    alias = node.children
        \\    alias[0u64] = node
        \\
        \\
        \\def main() -> i64:
        \\    cycle()
        \\    spare: list[Node] = []
        \\    _ = spare
        \\    return 42
    ;
    try t.expectEqual(@as(i64, 42), (try execute(source)).value);
}

// spec: GC-SOURCE-3
test "managed intermediate call arguments and record snapshots survive collection" {
    const source =
        \\class Holder:
        \\    values: list[i64]
        \\
        \\
        \\def make() -> list[i64]:
        \\    values: list[i64] = []
        \\    values.append(42)
        \\    return values
        \\
        \\
        \\def consume(first: Holder, second: list[i64]) -> i64:
        \\    second.append(9)
        \\    values = first.values
        \\    return values[0u64]
        \\
        \\
        \\def main() -> i64:
        \\    return consume(Holder(values=make()), [])
    ;
    try t.expectEqual(@as(i64, 42), (try execute(source)).value);
}

// spec: GC-SOURCE-4
test "managed bounds reads and writes produce located list bounds traps" {
    for ([_][]const u8{
        "return values[0u64]",
        "values[0u64] = 42\n    return 0",
    }) |operation| {
        const source = try std.fmt.allocPrint(t.allocator,
            \\def main() -> i64:
            \\    values: list[i64] = []
            \\    {s}
        , .{operation});
        defer t.allocator.free(source);
        const result = try execute(source);
        try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
        try t.expectEqualStrings("managed.my", result.trap.path);
        try t.expectEqual(@as(u64, 3), result.trap.line);
    }
}

// spec: GC-SOURCE-6
test "noalloc rejects transitive managed allocation while permitting fixed-slot mutation" {
    for ([_][]const u8{ "noalloc", "noalloc" }) |bound| {
        const create_source = try std.fmt.allocPrint(t.allocator,
            \\def make() -> list[i64]:
            \\    return []
            \\
            \\
            \\def constrained() -> list[i64] {s}:
            \\    return make()
            \\
            \\
            \\def main() -> i64:
            \\    return 0
            \\
        , .{bound});
        defer t.allocator.free(create_source);
        try reject(create_source, "E_EFFECT_BOUND");
        const append_source = try std.fmt.allocPrint(t.allocator,
            \\def grow(values: list[i64]) -> None:
            \\    values.append(42)
            \\
            \\
            \\def constrained(values: list[i64]) -> None {s}:
            \\    grow(values)
            \\
            \\
            \\def main() -> i64:
            \\    return 0
            \\
        , .{bound});
        defer t.allocator.free(append_source);
        try reject(append_source, "E_EFFECT_BOUND");
    }
    const source =
        \\def fixed(values: list[i64]) -> None effects(mutation) mutates(values):
        \\    values[0u64] = 42
        \\
        \\
        \\def inspect(values: list[i64]) -> i64 effects(mutation) mutates(values):
        \\    fixed(values)
        \\    return values[0u64]
        \\
        \\
        \\def main() -> i64:
        \\    values: list[i64] = []
        \\    values.append(0)
        \\    return inspect(values)
    ;
    try t.expectEqual(@as(i64, 42), (try execute(source)).value);
}

// spec: GC-SOURCE-11
test "managed cycles lose local and record roots on block break and continue exits" {
    const prefix =
        \\class Node:
        \\    children: list[Node]
        \\    value: i64
        \\
        \\
        \\class Holder:
        \\    nodes: list[Node]
    ;
    const bodies = [_][]const u8{
        \\    if True:
        \\        nodes: list[Node] = []
        \\        nodes.append(Node(children=nodes, value=42))
        \\        holder = Holder(nodes=nodes)
        \\        alias = holder.nodes
        \\        if len(alias) != 1:
        \\            return 1
        ,
        \\    while True:
        \\        nodes: list[Node] = []
        \\        nodes.append(Node(children=nodes, value=42))
        \\        holder = Holder(nodes=nodes)
        \\        alias = holder.nodes
        \\        if len(alias) != 1:
        \\            return 1
        \\        break
        ,
        \\    i = 0
        \\    while i < 1:
        \\        i = i + 1
        \\        nodes: list[Node] = []
        \\        nodes.append(Node(children=nodes, value=42))
        \\        holder = Holder(nodes=nodes)
        \\        alias = holder.nodes
        \\        if len(alias) != 1:
        \\            return 1
        \\        continue
        ,
    };
    for (bodies) |body| {
        const source = try std.mem.concat(t.allocator, u8, &.{ prefix, "\n\n\ndef main() -> i64:\n", body, "\n    spare: list[i64] = []\n    _ = spare\n    return 42\n" });
        defer t.allocator.free(source);
        try t.expectEqual(@as(i64, 42), (try execute(source)).value);
    }
}

// spec: GC-SOURCE-7
test "managed elements reject owned resources and unchecked results" {
    try rejectAll(&.{
        \\resource File: filesystem
        \\
        \\
        \\def main() -> i64:
        \\    values: list[File] = []
        \\    return len(values)
        ,
        \\resource File: filesystem
        \\
        \\
        \\class Wrapper:
        \\    file: File
        \\
        \\
        \\def main() -> i64:
        \\    values: list[Wrapper] = []
        \\    return len(values)
        ,
        \\result Answer:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def main() -> i64:
        \\    values: list[Answer] = []
        \\    return len(values)
        ,
    }, "E_GENERIC_REQUIREMENT");
}

// spec: GC-ROOTS-1
test "a managed alias keeps one identity and an aggregate snapshot roots its elements" {
    const source =
        \\class Holder:
        \\    items: list[i64]
        \\
        \\
        \\def total(holder: Holder) -> i64:
        \\    sum = 0
        \\    for item in holder.items:
        \\        sum = sum + item
        \\    return sum
        \\
        \\
        \\def main() -> i64:
        \\    values: list[i64] = []
        \\    alias = values
        \\    alias.append(11)
        \\    holder = Holder(items=values)
        \\    alias.append(31)
        \\    i = 0
        \\    while i < 40:
        \\        garbage: list[i64] = []
        \\        garbage.append(i)
        \\        i = i + 1
        \\    return total(holder)
    ;
    const result = try execute(source);
    try t.expectEqual(@as(i64, 42), result.value);
}

// spec: GC-CYCLES-1
test "an unreachable managed cycle is reclaimed while a reachable one survives collection" {
    const source =
        \\class Node:
        \\    links: list[Node]
        \\    value: i64
        \\
        \\
        \\def loop(value: i64) -> Node:
        \\    node = Node(links=[], value=value)
        \\    node.links.append(node)
        \\    return node
        \\
        \\
        \\def main() -> i64:
        \\    kept = loop(42)
        \\    i = 0
        \\    while i < 200:
        \\        _ = loop(i)
        \\        i = i + 1
        \\    inner = kept.links[0u64]
        \\    return inner.value
    ;
    const result = try execute(source);
    try t.expectEqual(@as(i64, 42), result.value);
}

// spec: GC-BOUNDARY-1
test "a managed list read past its initialized bounds is a located trap" {
    const source =
        \\def main() -> i64:
        \\    values: list[i64] = []
        \\    values.append(7)
        \\    return values[3u64]
    ;
    const result = try execute(source);
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
    try t.expectEqual(@as(u64, 4), result.trap.line);
}

// spec-case: QBE-ELEMENT-READ-1
test "scalar element reads load every width and keep a record read's copy" {
    const source =
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def main() -> i64:
        \\    narrow = [1i16, 2i16, 300i16]
        \\    flags = [True, False]
        \\    raw = b"abc"
        \\    total = i64(narrow[0]) + i64(narrow[-1]) + i64(narrow[1])
        \\    if flags[-1]:
        \\        total = total + 100
        \\    rows = [Pair(left=5, right=6)]
        \\    return total + rows[0].left + i64(raw[2])
    ;
    const result = try execute(source);
    try t.expectEqual(@as(i64, 407), result.value);
}

// spec-case: QBE-ELEMENT-READ-1
test "a scalar element read past the end keeps the original index in its detail" {
    const source =
        \\def main() -> i64:
        \\    values = [4, 5, 6]
        \\    return values[-4]
    ;
    const result = try execute(source);
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
    try t.expectEqual(@as(i64, -4), result.trap.detail.values.index);
    try t.expectEqual(@as(u64, 3), result.trap.detail.values.length);
}

// spec-case: QBE-ELEMENT-READ-1
test "negative element indexes count from the end for lists byte strings and text" {
    // A list index reaches the read already normalized by the checked frontend,
    // so the read only compares it unsigned. A byte string and a `str` pass the
    // caller's own index, so their reads keep the branchless sign adjustment
    // (`sar`/`and`/`add`): this pins the values that adjustment produces.
    const source =
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def main() -> i64:
        \\    values = [4, 5, 6]
        \\    names = ["red", "green"]
        \\    rows = [Pair(left=7, right=8)]
        \\    raw = b"abc"
        \\    text = "héllo"
        \\    return values[-1] + values[-len(values)] + len(names[-1]) + rows[-1].left + i64(raw[-1]) + i64(raw[-len(raw)]) + len(text[-1]) + len(text[-len(text)])
    ;
    const result = try execute(source);
    try t.expect(!result.trapped());
    try t.expectEqual(@as(i64, 6 + 4 + 5 + 7 + 99 + 97 + 1 + 1), result.value);
}

// spec: GC-CAPABILITY-1
test "a managed element declaration refuses a capability, directly or inside a record" {
    try rejectAll(&.{
        \\def main(fs: Filesystem) -> int:
        \\    values: list[Filesystem] = []
        \\    values.append(fs)
        \\    return len(values)
        ,
        \\class Holder:
        \\    fs: Filesystem
        \\
        \\
        \\def main(fs: Filesystem) -> int:
        \\    values: list[Holder] = []
        \\    values.append(Holder(fs=fs))
        \\    return len(values)
        ,
        \\class Holder:
        \\    fs: Filesystem
        \\
        \\
        \\class Outer:
        \\    holder: Holder
        \\
        \\
        \\def main(fs: Filesystem) -> int:
        \\    values: list[Outer] = []
        \\    values.append(Outer(holder=Holder(fs=fs)))
        \\    return len(values)
    }, "E_LIST_CAPABILITY");
}

// spec: QBE-TEXT-BLOCK-1
test "QBE-TEXT-BLOCK-1 run-time text shares one allocation with its payload" {
    const source =
        \\def main() -> i64:
        \\    keep: list[str] = []
        \\    for index in range(64):
        \\        text = "-".join(["a", "b", "c"])
        \\        keep.append(text.replace("-", "\u00e9") + text[0:2])
        \\    total = 0
        \\    for item in keep:
        \\        total = total + len(item)
        \\    if keep[0] != "a\u00e9b\u00e9ca-":
        \\        return 1
        \\    if keep[63] != "a\u00e9b\u00e9ca-":
        \\        return 2
        \\    return total
    ;
    // Every allocation collects under gc-stress, so a text whose block still
    // traced a pointer into its own allocation would corrupt or crash here
    // rather than merely leak.
    const result = try execute(source);
    try t.expectEqual(@as(i64, 64 * 7), result.value);
    try t.expectEqualStrings("", result.trap.code);
}

// spec: UTF8-TEXT-1
test "UTF8-TEXT-1 text stores UTF-8 octets and still indexes Unicode scalars" {
    // Scalar indexing, slicing, length, comparison, searching, case mapping,
    // classification, joining, padding, dictionary keys and byte interop all
    // run over a payload whose scalars are one, two, three and four octets
    // wide. A representation that answered any of them in octets, or that
    // cached a scalar count that drifted from the payload, disagrees here; the
    // mixed-width keys are what makes a dictionary's hashing and equality part
    // of the same check.
    const source =
        \\def main() -> i64:
        \\    text = "a\u00e9\u6f22b"
        \\    if len(text) != 4:
        \\        return 1
        \\    if text[0] != "a":
        \\        return 2
        \\    if text[1] != "\u00e9":
        \\        return 3
        \\    if text[2] != "\u6f22":
        \\        return 4
        \\    if text[-1] != "b":
        \\        return 5
        \\    if text[1:3] != "\u00e9\u6f22":
        \\        return 6
        \\    if text[3:99] != "b":
        \\        return 7
        \\    ordered = sorted(["\u6f22", "\u00e9", "a"])
        \\    if ordered[0] != "a":
        \\        return 8
        \\    if ordered[1] != "\u00e9":
        \\        return 9
        \\    if ordered[2] != "\u6f22":
        \\        return 10
        \\    if text == "ab":
        \\        return 37
        \\    if "a\u00e9" != "a" + "\u00e9":
        \\        return 10
        \\    if ord("\u00e9") != 233:
        \\        return 11
        \\    if chr(233) != "\u00e9":
        \\        return 12
        \\    if len(chr(128512)) != 1:
        \\        return 13
        \\    if chr(128512) != "\U0001f600":
        \\        return 14
        \\    if "aXbXc".replace("X", "\u00e9") != "a\u00e9b\u00e9c":
        \\        return 15
        \\    if "a\u00e9b\u00e9c".count("\u00e9") != 2:
        \\        return 16
        \\    if "a\u00e9b\u00e9c".find("\u00e9") != 1:
        \\        return 17
        \\    if "a\u00e9b\u00e9c".find("c") != 4:
        \\        return 18
        \\    if "a\u00e9b\u00e9c".find("\u6f22") != -1:
        \\        return 19
        \\    if len("a\u00e9,b".split(",")) != 2:
        \\        return 20
        \\    if "a\u00e9,b".split(",")[0] != "a\u00e9":
        \\        return 21
        \\    if "-".join(["\u00e9", "\u6f22"]) != "\u00e9-\u6f22":
        \\        return 22
        \\    if "\u00c9a".upper() != "\u00c9A":
        \\        return 23
        \\    if not "aB".isalpha():
        \\        return 24
        \\    if "\u00e9".isalpha():
        \\        return 38
        \\    if "\u00e9".isdigit():
        \\        return 25
        \\    if "  \u00e9 ".strip() != "\u00e9":
        \\        return 26
        \\    if "a\u00e9".zfill(4) != "00a\u00e9":
        \\        return 27
        \\    counts: dict[str, int] = {}
        \\    counts["\u00e9"] = 1
        \\    counts["\u6f22"] = 2
        \\    counts["\u00e9"] = counts["\u00e9"] + 1
        \\    if counts["\u00e9"] != 2:
        \\        return 28
        \\    if counts["\u6f22"] != 2:
        \\        return 29
        \\    if len(counts) != 2:
        \\        return 30
        \\    if "\u00e9" not in counts:
        \\        return 31
        \\    total = 0
        \\    for letter in text:
        \\        total = total + len(letter)
        \\    if total != 4:
        \\        return 32
        \\    if len(text.encode()) != 7:
        \\        return 33
        \\    match text.encode().decode():
        \\        case Ok(value):
        \\            if value != text:
        \\                return 34
        \\        case Err(message):
        \\            return 35
        \\    if len("a\u00e9".splitlines()) != 1:
        \\        return 36
        \\    return 1234
    ;
    const result = try execute(source);
    try t.expectEqual(@as(i64, 1234), result.value);
    try t.expectEqualStrings("", result.trap.code);
}

// spec: GC-OBJECT-1
test "GC-OBJECT-1 a two-word header fits thousands of live lists under one budget" {
    // Each live four-element `list[i64]` costs one 72-byte list header object
    // plus a 32-byte backing; the two-word header is what lets four thousand of
    // them stay inside one mebibyte. The retired 96-byte header charged roughly
    // twice that and trapped here, so the budget is the observable half of the
    // representation change.
    var compilation = try language.Compilation.init(t.allocator, "header.my",
        \\def main() -> i64:
        \\    values: list[list[i64]] = []
        \\    n = 0
        \\    while n < 4000:
        \\        values.append([n, n + 1, n + 2, n + 3])
        \\        n += 1
        \\    return values[3999][3]
    );
    defer compilation.deinit();
    const result = try native.runWithOptions(&compilation, .{ .max_memory = 1 << 20 });
    try t.expectEqual(@as(i64, 4002), result.value);
    try t.expectEqualStrings("", result.trap.code);
}

// spec: GC-SEGMENT-1
test "GC-SEGMENT-1 a churn loop reuses reclaimed slots without stale fields" {
    // Every allocation collects under gc-stress, so each iteration's scratch list
    // is swept and its slots come back through the size-class free list. A slot
    // handed out with a stale `length` or `capacity` would corrupt the retained
    // copies, and a slot whose payload was not zeroed would publish the previous
    // owner's storage pointer.
    var compilation = try language.Compilation.init(t.allocator, "segments.my",
        \\def main() -> i64:
        \\    keep: list[list[i64]] = []
        \\    n = 0
        \\    while n < 20000:
        \\        scratch = [n, n + 1, n + 2, n + 3]
        \\        if n % 1000 == 0:
        \\            keep.append(scratch)
        \\        n += 1
        \\    total = 0
        \\    for item in keep:
        \\        total = total + item[3]
        \\    return total
    );
    defer compilation.deinit();
    const result = try native.runWithOptions(&compilation, .{ .gc_stress = true });
    try t.expectEqual(@as(i64, 190060), result.value);
    try t.expectEqualStrings("", result.trap.code);
}

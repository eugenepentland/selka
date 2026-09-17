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

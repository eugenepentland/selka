//! Source-level managed aliases, VM rooting, effects, and storage boundaries.
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

fn reject(text: []const u8, expected: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-managed.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(expected, compilation.diagnostics.items[0].code);
}

fn rejectAll(sources: []const []const u8, code: []const u8) !void {
    for (sources) |source| try reject(source, code);
}

// spec: GC-SOURCE-9
test "bytecode rejects managed metadata on an ordinary aggregate" {
    var compilation = try language.Compilation.init(t.allocator, "forged-managed.my",
        \\class Record:
        \\    value: i64
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
    records[0].managed = true;
    program.records = records;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
}

// spec: GC-SOURCE-1
test "managed aliases mutate immutable bindings across helpers without allocator authority" {
    const source =
        \\def change(values: List[i64]):
        \\    values.push(40)
        \\    values[0u64] = 42
        \\
        \\
        \\def main() -> i64:
        \\    values: List[i64] = []
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
        \\    children: List[Node]
        \\    value: i64
        \\
        \\
        \\def cycle():
        \\    nodes: List[Node] = []
        \\    nodes.push(Node(children=nodes, value=42))
        \\    node = nodes[0u64]
        \\    alias = node.children
        \\    alias[0u64] = node
        \\
        \\
        \\def main() -> i64:
        \\    cycle()
        \\    spare: List[Node] = []
        \\    _ = spare
        \\    return 42
    ;
    try t.expectEqual(@as(i64, 42), (try execute(source)).value);
}

// spec: GC-SOURCE-3
test "managed intermediate call arguments and record snapshots survive collection" {
    const source =
        \\class Holder:
        \\    values: List[i64]
        \\
        \\
        \\def make() -> List[i64]:
        \\    values: List[i64] = []
        \\    values.push(42)
        \\    return values
        \\
        \\
        \\def consume(first: Holder, second: List[i64]) -> i64:
        \\    second.push(9)
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
            \\    values: List[i64] = []
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
            \\def make() -> List[i64]:
            \\    return []
            \\
            \\
            \\def constrained() -> List[i64] {s}:
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
            \\def grow(values: List[i64]) -> None:
            \\    values.push(42)
            \\
            \\
            \\def constrained(values: List[i64]) -> None {s}:
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
        \\def fixed(values: List[i64]) noalloc:
        \\    values[0u64] = 42
        \\
        \\
        \\def inspect(values: List[i64]) -> i64 noalloc:
        \\    fixed(values)
        \\    return values[0u64]
        \\
        \\
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.push(0)
        \\    return inspect(values)
    ;
    try t.expectEqual(@as(i64, 42), (try execute(source)).value);
}

// spec: GC-SOURCE-11
test "managed cycles lose local and record roots on block break and continue exits" {
    const prefix =
        \\class Node:
        \\    children: List[Node]
        \\    value: i64
        \\
        \\
        \\class Holder:
        \\    nodes: List[Node]
    ;
    const bodies = [_][]const u8{
        \\    if True:
        \\        nodes: List[Node] = []
        \\        nodes.push(Node(children=nodes, value=42))
        \\        holder = Holder(nodes=nodes)
        \\        alias = holder.nodes
        \\        if len(alias) != 1:
        \\            return 1
        ,
        \\    while True:
        \\        nodes: List[Node] = []
        \\        nodes.push(Node(children=nodes, value=42))
        \\        holder = Holder(nodes=nodes)
        \\        alias = holder.nodes
        \\        if len(alias) != 1:
        \\            return 1
        \\        break
        ,
        \\    i = 0
        \\    while i < 1:
        \\        i = i + 1
        \\        nodes: List[Node] = []
        \\        nodes.push(Node(children=nodes, value=42))
        \\        holder = Holder(nodes=nodes)
        \\        alias = holder.nodes
        \\        if len(alias) != 1:
        \\            return 1
        \\        continue
        ,
    };
    for (bodies) |body| {
        const source = try std.mem.concat(t.allocator, u8, &.{ prefix, "\n\n\ndef main() -> i64:\n", body, "\n    spare: List[i64] = []\n    _ = spare\n    return 42\n" });
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
        \\    values: List[File] = []
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
        \\    values: List[Wrapper] = []
        \\    return len(values)
        ,
        \\result Answer:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def main() -> i64:
        \\    values: List[Answer] = []
        \\    return len(values)
        ,
    }, "E_GENERIC_REQUIREMENT");
}

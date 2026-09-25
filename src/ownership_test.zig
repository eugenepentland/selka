//! The ownership analysis on hand-written functions with known answers
//! (`OWNERSHIP-ANALYSIS-1`), read through the explain surface
//! (`OWNERSHIP-EXPLAIN-1`) exactly as `mylang check --explain-ownership` prints it.
const std = @import("std");
const language = @import("compiler.zig");
const liveness = @import("qbe_liveness.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");

const Local = struct { index: u32, name: []const u8, role: []const u8, parent: ?u32 = null };
const Origin = struct { origin: []const u8, local: ?u32 = null, part: ?[]const u8 = null };
const Transfer = struct { pc: u32, kind: []const u8, target: ?u32 = null, source: Origin, class: []const u8 };
const Cow = struct { pc: u32, local: u32, via: u32, elements: bool, needed: bool, hoisted: ?u32 };
const Function = struct { function: []const u8, locals: []Local, transfers: []Transfer, cow: []Cow, moves: []u32 };

/// The explanation of function `name` in `source`.
fn explained(a: std.mem.Allocator, source: []const u8, name: []const u8) !std.json.Parsed(Function) {
    var c = try language.Compilation.init(a, "ownership.my", source);
    defer c.deinit();
    const text = try c.explainOwnership(a);
    defer a.free(text);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(Function, a, line, .{ .allocate = .alloc_always });
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

//! Recursive and shared type graphs that hold capabilities. Before 5C the front end walked the type graph under every
//! local and return type and refused an owning provider outside an ordinary record; a capability is a scalar handle now,
//! so every one of these programs, a provider in an enum payload, an optional provider below a record and a returned
//! record of one included, is accepted.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// What a fixture's first error was: its code and the source text it points at.
const Refusal = struct { code: []const u8, at: []const u8 };

/// Check `text`; null when it is accepted, else its first error.
fn firstRefusal(arena: std.mem.Allocator, text: []const u8) !?Refusal {
    const report = try fixture.check(arena, text);
    const item = report.firstError() orelse return null;
    return .{ .code = item.code, .at = report.text(item.span) };
}

/// Require that `text` is accepted, naming its first error when it is not.
fn expectAccepted(arena: std.mem.Allocator, text: []const u8) !void {
    const found = try firstRefusal(arena, text);
    try t.expectEqual(@as(?Refusal, null), found);
}

/// A recursive enum reached only through lists, beside plain records.
const recursive_enum =
    \\enum Tree:
    \\    leaf
    \\    node(value: Tree[])
    \\
    \\record Forest:
    \\    trees: Tree[]
    \\    count: int
    \\
    \\func use(forest: Forest, again: Forest) -> int:
    \\    return forest.count + again.count
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "storage rules: a recursive enum that holds no provider is accepted" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expect(try firstRefusal(arena.allocator(), recursive_enum) == null);
}

/// A provider held directly by a plain record whose other field is a recursive type.
const provider_beside_recursion =
    \\enum Tree:
    \\    leaf
    \\    node(value: Tree[])
    \\
    \\record Forest:
    \\    trees: Tree[]
    \\
    \\record Host:
    \\    clock: Clock
    \\    forest: Forest
    \\
    \\func use(host: Host, other: Host) -> int:
    \\    return len(host.forest.trees) + len(other.forest.trees)
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "storage rules: a provider in a plain record beside a recursive type is accepted for every local of it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expect(try firstRefusal(arena.allocator(), provider_beside_recursion) == null);
}

/// Two enums that hold each other through lists, with a provider record that holds both.
const mutual_recursion =
    \\enum Even:
    \\    zero
    \\    next(value: Odd[])
    \\
    \\enum Odd:
    \\    one(value: Even[])
    \\
    \\record Host:
    \\    clock: Clock
    \\    even: Even
    \\    odd: Odd
    \\
    \\func use(host: Host, even: Even, odd: Odd) -> int:
    \\    return 0
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "storage rules: mutually recursive enums beside a provider record are accepted" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expect(try firstRefusal(arena.allocator(), mutual_recursion) == null);
}

/// A provider carried by an enum payload, which is not an ordinary record.
const provider_in_enum =
    \\enum Slot:
    \\    held(clock: Clock)
    \\    empty
    \\
    \\func use(slot: Slot) -> int:
    \\    return 0
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "storage rules: a provider in an enum payload is accepted (5C)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try expectAccepted(arena.allocator(), provider_in_enum);
}

/// A recursive root, and a later root that holds an optional provider below a record.
const clean_root_then_refused =
    \\enum Even:
    \\    zero
    \\    next(value: Odd[])
    \\
    \\enum Odd:
    \\    one(value: Even[])
    \\
    \\record Wrapped:
    \\    even: Even
    \\    clock: Clock?
    \\
    \\func first(left: Even, again: Even) -> int:
    \\    return 0
    \\
    \\func second(right: Wrapped) -> int:
    \\    return 0
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "storage rules: a recursive root beside an optional provider below a record is accepted (5C)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try expectAccepted(arena.allocator(), clean_root_then_refused);
}

/// A record of an optional provider, returned after parameters of capabilities.
const refused_return_type =
    \\record Config:
    \\    clock: Clock?
    \\
    \\func make(clock: Clock) -> Config:
    \\    return Config(clock=Some(clock))
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "storage rules: a returned record of an optional provider is accepted (5C)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try expectAccepted(arena.allocator(), refused_return_type);
}

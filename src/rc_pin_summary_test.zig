//! COW-PIN-ELIDE-1: a `mut` list argument is pinned across the call unless the
//! callee's whole-program summary proves it never shares the parameter. Each
//! test lowers a small program under the RC runtime and counts the caller's
//! scope operations: none when the pin is elided, one begin, pin and end when not.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime_mode = @import("runtime_mode.zig");
const t = std.testing;

const Scopes = struct { begin: usize, pin: usize, end: usize };

const Emitted = struct { functions: []const struct { name: []const u8, il: []const u8 } };

const pinned: Scopes = .{ .begin = 1, .pin = 1, .end = 1 };
const elided: Scopes = .{ .begin = 0, .pin = 0, .end = 0 };

fn occurrences(text: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, text, needle);
}

/// Inline journal operations retain exactly one native refusal path each.
fn scopes(source: []const u8, caller: []const u8) !Scopes {
    const saved = runtime_mode.get();
    defer runtime_mode.set(saved);
    runtime_mode.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "pin_elide.my", source);
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    var parsed = try std.json.parseFromSlice(Emitted, t.allocator, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value.functions) |function| if (std.mem.eql(u8, function.name, caller)) {
        const il = function.il;
        const result: Scopes = .{
            .begin = occurrences(il, "# RC-SCOPE-IL-1 begin"),
            .pin = occurrences(il, "# RC-SCOPE-IL-1 pin"),
            .end = occurrences(il, "# RC-SCOPE-IL-1 end"),
        };
        try t.expectEqual(@as(usize, 0), occurrences(il, "call $myl_qbe_rc_scope_begin"));
        try t.expectEqual(result.pin, occurrences(il, "call $myl_qbe_rc_scope_pin"));
        try t.expectEqual(result.end, occurrences(il, "call $myl_qbe_rc_scope_end"));
        if (result.pin != 0) {
            try t.expect(std.mem.indexOf(u8, il, "$myl_native_list_header_type") != null);
            try t.expect(std.mem.indexOf(u8, il, "# myl-rc-state") != null);
            try t.expect(std.mem.indexOf(u8, il, "@rcspincommit") != null);
        }
        return result;
    };
    return error.TestUnexpectedResult;
}

// spec: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a callee that only reads and writes elements needs no pin" {
    try t.expectEqual(elided, try scopes(
        \\def bump(xs: mut list[int], i: int) -> int:
        \\    xs[i] = xs[i] + 1
        \\    return len(xs)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return bump(mut xs, 0)
    , "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a self recursive sort and its swap helper need no pin" {
    const source =
        \\def swap(xs: mut list[int], i: int, j: int):
        \\    tmp = xs[i]
        \\    xs[i] = xs[j]
        \\    xs[j] = tmp
        \\def sort(xs: mut list[int], lo: int, hi: int):
        \\    if lo >= hi:
        \\        return
        \\    if xs[lo] > xs[hi]:
        \\        swap(mut xs, lo, hi)
        \\    sort(mut xs, lo + 1, hi)
        \\def main() -> int:
        \\    xs = [3, 1, 2]
        \\    sort(mut xs, 0, 2)
        \\    return xs[0]
    ;
    try t.expectEqual(elided, try scopes(source, "main"));
    try t.expectEqual(elided, try scopes(source, "sort"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 mutually recursive callees keep the summary" {
    const source =
        \\def ping(xs: mut list[int], n: int) -> int:
        \\    if n <= 0:
        \\        return len(xs)
        \\    xs[0] = xs[0] + 1
        \\    return pong(mut xs, n - 1)
        \\def pong(xs: mut list[int], n: int) -> int:
        \\    if n <= 0:
        \\        return len(xs)
        \\    xs[0] = xs[0] + 2
        \\    return ping(mut xs, n - 1)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return ping(mut xs, 3)
    ;
    try t.expectEqual(elided, try scopes(source, "main"));
    try t.expectEqual(elided, try scopes(source, "ping"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a callee that grows the list keeps the pin" {
    try t.expectEqual(pinned, try scopes(
        \\def grow(xs: mut list[int]) -> int:
        \\    xs.append(3)
        \\    return len(xs)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return grow(mut xs)
    , "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a callee that iterates the list keeps the pin" {
    try t.expectEqual(pinned, try scopes(
        \\def total(xs: mut list[int]) -> int:
        \\    xs[0] = 5
        \\    sum = 0
        \\    for x in xs:
        \\        sum = sum + x
        \\    return sum
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return total(mut xs)
    , "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a callee that snapshots the list keeps the pin" {
    try t.expectEqual(pinned, try scopes(
        \\def snap(xs: mut list[int]) -> int:
        \\    copy = xs
        \\    xs[0] = 9
        \\    return copy[0]
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return snap(mut xs)
    , "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a callee that stores the list in a record keeps the pin" {
    try t.expectEqual(pinned, try scopes(
        \\record Holder:
        \\    items: list[int]
        \\def keep(xs: mut list[int]) -> int:
        \\    xs[0] = 9
        \\    holder = Holder(xs)
        \\    return len(holder.items)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return keep(mut xs)
    , "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a callee that stores the list in a list or a dictionary keeps the pin" {
    const source =
        \\def nest(xs: mut list[int]) -> int:
        \\    xs[0] = 9
        \\    rows: list[list[int]] = []
        \\    rows.append(xs)
        \\    return len(rows)
        \\def index(xs: mut list[int]) -> int:
        \\    xs[0] = 9
        \\    table: dict[int, list[int]] = {}
        \\    table[1] = xs
        \\    return len(table)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return nest(mut xs) + index(mut xs)
    ;
    try t.expectEqual(Scopes{ .begin = 2, .pin = 2, .end = 2 }, try scopes(source, "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a callee that returns the list keeps the pin" {
    try t.expectEqual(pinned, try scopes(
        \\def give(xs: mut list[int]) -> list[int]:
        \\    xs[0] = 9
        \\    return xs
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    ys = give(mut xs)
        \\    return len(ys)
    , "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 passing the list to a read-only parameter keeps the pin" {
    try t.expectEqual(pinned, try scopes(
        \\def peek(xs: list[int]) -> int:
        \\    return len(xs)
        \\def look(xs: mut list[int]) -> int:
        \\    xs[0] = 9
        \\    return peek(xs)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return look(mut xs)
    , "main"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 forwarding to a callee that is not summarised keeps the pin" {
    const source =
        \\def grow(xs: mut list[int]) -> int:
        \\    xs.append(3)
        \\    return len(xs)
        \\def relay(xs: mut list[int]) -> int:
        \\    xs[0] = 9
        \\    return grow(mut xs)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return relay(mut xs)
    ;
    try t.expectEqual(pinned, try scopes(source, "main"));
    try t.expectEqual(pinned, try scopes(source, "relay"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a recursive callee that grows on one path keeps the pin at every level" {
    const source =
        \\def descend(xs: mut list[int], n: int) -> int:
        \\    if n == 0:
        \\        xs.append(1)
        \\        return len(xs)
        \\    xs[0] = xs[0] + 1
        \\    return descend(mut xs, n - 1)
        \\def main() -> int:
        \\    xs = [1, 2]
        \\    return descend(mut xs, 2)
    ;
    try t.expectEqual(pinned, try scopes(source, "main"));
    try t.expectEqual(pinned, try scopes(source, "descend"));
}

// spec-case: COW-PIN-ELIDE-1
test "COW-PIN-ELIDE-1 a list held in a record field is not a local and keeps the pin" {
    try t.expectEqual(pinned, try scopes(
        \\record Holder:
        \\    items: list[int]
        \\def bump(xs: mut list[int]):
        \\    xs[0] = xs[0] + 1
        \\def main() -> int:
        \\    holder = Holder([1, 2])
        \\    bump(mut holder.items)
        \\    return holder.items[0]
    , "main"));
}

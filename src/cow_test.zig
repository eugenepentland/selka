//! Copy-on-write value semantics over the tracing collector (D9 stage 3b):
//! the checks, shares, pins and loop-entry checks the native emitter lowers
//! under the internal switch, read from the emitted QBE IL, and the programs
//! that switch changes the meaning of, run natively, under collection stress
//! too.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Policy = @import("native_interface.zig").Policy;
const value_semantics = @import("value_semantics.zig");

const Unit = struct { name: []const u8, symbol: []const u8, il: []const u8 };
const Manifest = struct { functions: []Unit };

/// The QBE IL of function `name` in `source`, emitted under `policy`.
fn unitText(a: std.mem.Allocator, source: []const u8, name: []const u8, policy: Policy) ![]const u8 {
    var c = try language.Compilation.init(a, "cow.my", source);
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, policy);
    defer a.free(manifest);
    const parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return a.dupe(u8, unit.il);
    return error.TestUnexpectedResult;
}

fn count(text: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, text, needle);
}

/// The unaccounted protocol a published executable uses, with copy on write.
const checks: Policy = .{ .step_checks = false, .frame_checks = false, .cow = .checks };
/// The same protocol without it.
const plain: Policy = .{ .step_checks = false, .frame_checks = false };
/// The inline shared-flag test every check spells.
const shared_test = ", 61\n";
/// The pinned flag a pin sets.
const pin_set = " or ";

/// Run `source` natively under copy on write and answer its result.
fn run(a: std.mem.Allocator, source: []const u8, stress: bool) !i64 {
    var c = try language.Compilation.init(a, "cow.my", source);
    defer c.deinit();
    const result = try native.runWithPolicy(&c, checks, .{ .gc_stress = stress });
    if (result.trapped()) return error.TestUnexpectedResult;
    return result.value;
}

const assigned =
    \\def main() -> int:
    \\    xs: list[int] = [1, 2]
    \\    ys = xs
    \\    ys.append(3)
    \\    return len(xs) * 10 + len(ys)
;

// spec: QBE-VALUECOPY-BORROW-1
test "copy on write: payload return copies straight into the private transfer scratch" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\record Box:
        \\    items: list[int]
        \\    number: int
        \\
        \\union Item:
        \\    box: Box,
        \\    empty
        \\
        \\def take(items: list[Item]) -> Box:
        \\    match items[0]:
        \\        case Item.box(payload):
        \\            return payload
        \\        case Item.empty:
        \\            return Box([], 0)
        \\
        \\def main() -> int:
        \\    items = [Item.box(Box([1], 7))]
        \\    copied = take(items)
        \\    copied.items.append(2)
        \\    return len(take(items).items) * 10 + len(copied.items)
    ;
    const a = std.testing.allocator;
    const il = try unitText(a, source, "take", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 0), count(il, "blit %l"));
    try std.testing.expect(count(il, "call $myl_qbe_cow_transfer(") > 0);
}

// spec: QBE-VALUECOPY-ROOTS-1
test "copy on write: inline transfer publishes roots only in its allocating fallback" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\def snapshot(xs: list[int]) -> list[int]:
        \\    return xs
        \\
        \\def main() -> int:
        \\    return len(snapshot([1]))
    ;
    const a = std.testing.allocator;
    const il = try unitText(a, source, "snapshot", checks);
    defer a.free(il);
    const slow = std.mem.indexOf(u8, il, "\n@vcslow") orelse return error.TestUnexpectedResult;
    const publication = std.mem.indexOf(u8, il, " storel %root0,") orelse return error.TestUnexpectedResult;
    const call = std.mem.indexOf(u8, il, "call $myl_qbe_cow_transfer(") orelse return error.TestUnexpectedResult;
    const done = std.mem.indexOf(u8, il, "\n@vcdone") orelse return error.TestUnexpectedResult;
    try std.testing.expect(slow < publication and publication < call and call < done);
    try std.testing.expectEqual(@as(usize, 0), count(il[0..slow], " storel %root"));
    try std.testing.expectEqual(@as(usize, 1), count(il[call..done], " storel %root_mark,"));
}

// spec: QBE-VARIANT-ELEMENT-1
test "copy on write: immediate variant dispatch copies only its selected payload" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\record Pair:
        \\    first: int
        \\    second: int
        \\
        \\union Item:
        \\    pair: Pair,
        \\    empty
        \\
        \\def read(items: list[Item], index: int) -> int:
        \\    match items[index]:
        \\        case Item.pair(payload):
        \\            return payload.first + payload.second
        \\        case Item.empty:
        \\            return 0
        \\
        \\def main() -> int:
        \\    return read([Item.pair(Pair(1, 2))], -1)
    ;
    const a = std.testing.allocator;
    const il = try unitText(a, source, "read", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 1), count(il, " blit "));
    try std.testing.expect(count(il, "myl_qbe_fail_normalized_index_bounds") > 0);
    try std.testing.expectEqual(@as(i64, 3), try run(a, source, true));
}

// spec: COW-SHARED-1
test "copy on write: a copy transfer shares the list and the first write through either name copies it" {
    // Retain the internal phase-one path during the explicit legacy window.
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    try std.testing.expectEqual(@as(i64, 23), try run(std.testing.allocator, assigned, false));
    try std.testing.expectEqual(@as(i64, 23), try run(std.testing.allocator, assigned, true));
    const a = std.testing.allocator;
    const il = try unitText(a, assigned, "main", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 1), count(il, "call $myl_native_cow_share("));
    try std.testing.expectEqual(@as(usize, 1), count(il, "2305843009213693952\n storel"));
}

// spec-case: COW-SHARED-1
test "copy on write: value-semantics copies use the rooted COW hook without duplicate transfer marks" {
    const previous = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(previous);
    try std.testing.expectEqual(@as(i64, 23), try run(std.testing.allocator, assigned, true));
    const a = std.testing.allocator;
    const il = try unitText(a, assigned, "main", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 1), count(il, "call $myl_qbe_cow_transfer("));
    try std.testing.expectEqual(@as(usize, 0), count(il, "call $myl_native_cow_share("));
    try std.testing.expectEqual(@as(usize, 1), count(il, "\n@vcpresent"));
    const transfer = std.mem.indexOf(u8, il, "call $myl_qbe_cow_transfer(") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfScalarPos(u8, il, transfer, '\n') orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, il[transfer..end], "%s") == null);
}

// spec-case: COW-SHARED-1
test "copy on write: a flat record shares two leaves inline with a rooted pinned fallback" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\record Pair:
        \\    first: list[int]
        \\    second: list[int]
        \\
        \\def main() -> int:
        \\    original = Pair(first=[1], second=[2])
        \\    copied = original
        \\    copied.first.append(3)
        \\    return len(original.first) * 100 + len(copied.first) * 10 + len(copied.second)
    ;
    try std.testing.expectEqual(@as(i64, 121), try run(std.testing.allocator, source, true));
    const a = std.testing.allocator;
    const il = try unitText(a, source, "main", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 2), count(il, "\n@vcpresent"));
    try std.testing.expectEqual(@as(usize, 1), count(il, "call $myl_qbe_cow_transfer("));
}

// spec-case: COW-NESTED-1
test "copy on write: recursive box projection protects a child exposed before a later box copy" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\record Branch:
        \\    items: list[int]
        \\    next: Option[Branch]
        \\
        \\def main() -> int:
        \\    root = Branch(items=[0], next=Some(Branch(items=[1], next=None)))
        \\    exposed = root.next
        \\    copied = root
        \\    if exposed is None:
        \\        return 0
        \\    exposed.items.append(2)
        \\    old = copied.next
        \\    if old is None:
        \\        return 0
        \\    return len(old.items) * 10 + len(exposed.items)
    ;
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, source, false));
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, source, true));
    const a = std.testing.allocator;
    const il = try unitText(a, source, "main", checks);
    defer a.free(il);
    try std.testing.expect(count(il, "call $myl_qbe_cow_unbox(") > 0);
    // A zero-length array makes a direct recursive record-field cycle
    // inhabitable. A nested write must detach that box before writeback.
    const direct =
        \\record A:
        \\    child: B
        \\
        \\record B:
        \\    items: list[int]
        \\    tail: [0]A
        \\
        \\def main() -> int:
        \\    first = A(child=B(items=[1], tail=[]))
        \\    changed = first
        \\    changed.child.items.append(2)
        \\    return len(first.child.items) * 10 + len(changed.child.items)
    ;
    try std.testing.expectEqual(@as(i64, 12), try run(a, direct, false));
    try std.testing.expectEqual(@as(i64, 12), try run(a, direct, true));
    const direct_il = try unitText(a, direct, "main", checks);
    defer a.free(direct_il);
    try std.testing.expect(count(direct_il, "call $myl_native_cow_clone_box(") > 0);
    const element =
        \\record A:
        \\    child: B
        \\
        \\record B:
        \\    items: list[int]
        \\    tail: [0]A
        \\
        \\def main() -> int:
        \\    first = A(child=B(items=[1], tail=[]))
        \\    values: list[A] = [first]
        \\    values[0].child.items.append(2)
        \\    return len(first.child.items) * 10 + len(values[0].child.items)
    ;
    try std.testing.expectEqual(@as(i64, 12), try run(a, element, true));
    const pure_call =
        \\record A:
        \\    child: B
        \\
        \\record B:
        \\    items: list[int]
        \\    tail: [0]A
        \\
        \\def set_first(xs: mut list[int]) -> None:
        \\    xs[0] = 7
        \\
        \\def main() -> int:
        \\    sibling = [[11], [22], [33]]
        \\    original = A(child=B(items=[1], tail=[]))
        \\    changed = original
        \\    set_first(mut changed.child.items)
        \\    if sibling[0][0] == 11 and sibling[2][0] == 33 and original.child.items == [1] and changed.child.items == [7]:
        \\        return 1
        \\    return 0
    ;
    try std.testing.expectEqual(@as(i64, 1), try run(a, pure_call, true));
}

// spec: QBE-PURE-BOX-READ-1
test "copy on write: a pure recursive box read needs no COW unbox runtime" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\record Node:
        \\    number: int
        \\    next: Option[Node]
        \\
        \\def total(node: Node) -> int:
        \\    child = node.next
        \\    if child is None:
        \\        return node.number
        \\    return node.number + total(child)
        \\
        \\def main() -> int:
        \\    return total(Node(1, Some(Node(2, None))))
    ;
    const a = std.testing.allocator;
    const il = try unitText(a, source, "total", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 0), count(il, "call $myl_qbe_cow_unbox("));
    try std.testing.expectEqual(@as(i64, 3), try run(a, source, true));
}

// spec: COW-UNIQUE-1
test "copy on write: every in-place write tests one header bit inline and copies only on the shared path" {
    const a = std.testing.allocator;
    const source =
        \\def fill(n: int) -> list[int]:
        \\    out: list[int] = []
        \\    out.append(n)
        \\    out.append(n + 1)
        \\    return out
        \\
        \\
        \\def main() -> int:
        \\    return len(fill(2))
    ;
    const il = try unitText(a, source, "fill", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 2), count(il, shared_test));
    try std.testing.expectEqual(@as(usize, 2), count(il, "call $myl_native_cow_unique(l %heap"));
    const off = legacy: {
        const scope = @import("test_support.zig").LegacySharing.enter();
        defer scope.restore();
        break :legacy try unitText(a, source, "fill", plain);
    };
    defer a.free(off);
    try std.testing.expectEqual(@as(usize, 0), count(off, "cow"));
    try std.testing.expectEqual(@as(i64, 2), try run(std.testing.allocator, source, true));
}

const hoisted =
    \\def main() -> int:
    \\    xs: list[int] = [0]
    \\    ys = xs
    \\    for i in range(10):
    \\        ys.append(i)
    \\    return len(xs) * 100 + len(ys)
;

// spec: COW-HOIST-1
test "copy on write: a check the loop cannot invalidate runs once on the loop's entry edges" {
    const a = std.testing.allocator;
    const il = try unitText(a, hoisted, "main", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 1), count(il, "\n@ce"));
    const entry = std.mem.indexOf(u8, il, "\n@ce").?;
    const header_end = std.mem.indexOfPos(u8, il, entry, "@cowkeep").?;
    try std.testing.expectEqual(@as(usize, 1), count(il[entry..header_end], shared_test));
    try std.testing.expectEqual(@as(i64, 111), try run(std.testing.allocator, hoisted, false));
    try std.testing.expectEqual(@as(i64, 111), try run(std.testing.allocator, hoisted, true));
}

const matrix =
    \\def main() -> int:
    \\    grid = [[0, 0], [0, 5]]
    \\    saved = grid
    \\    for i in range(2):
    \\        for j in range(2):
    \\            grid[i][j] = i * 2 + j + 1
    \\    return saved[1][1] * 100 + grid[1][1]
;

// spec-case: COW-HOIST-1
test "copy on write: a nested write in a loop makes the rows unique once, on entry" {
    const a = std.testing.allocator;
    const il = try unitText(a, matrix, "main", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 1), count(il, "call $myl_native_cow_elements("));
    try std.testing.expectEqual(@as(i64, 504), try run(std.testing.allocator, matrix, false));
    try std.testing.expectEqual(@as(i64, 504), try run(std.testing.allocator, matrix, true));
}

const nested =
    \\def main() -> int:
    \\    grid = [[1, 2], [3, 4]]
    \\    snapshot = grid
    \\    grid[1][0] = 7
    \\    grid[0].append(5)
    \\    return snapshot[1][0] * 1000 + len(snapshot[0]) * 100 + grid[1][0] * 10 + len(grid[0])
;

// spec: COW-NESTED-1
test "copy on write: a write through a nested element makes each level unique and writes the copy back" {
    const a = std.testing.allocator;
    const il = try unitText(a, nested, "main", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 2), count(il, "call $myl_native_cow_unique_in("));
}

const entries =
    \\def main() -> int:
    \\    d: dict[str, list[int]] = {"a": [1]}
    \\    before = d
    \\    d["a"].append(2)
    \\    d["a"][0] = 9
    \\    return len(before["a"]) * 1000 + before["a"][0] * 100 + len(d["a"]) * 10 + d["a"][0]
;

// spec-case: COW-NESTED-1
test "copy on write: a write through a dictionary value copies the dictionary and the value" {
    const a = std.testing.allocator;
    const il = try unitText(a, entries, "main", checks);
    defer a.free(il);
    try std.testing.expect(count(il, "call $myl_native_cow_unique_in(") >= 1);
}

// spec-case: COW-NESTED-1
test "copy on write: alternating collection owners keep both snapshots alive under GC stress" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\def main() -> int:
        \\    original: list[dict[str, dict[str, list[int]]]] = [{"a": {"b": [1]}}]
        \\    changed = original
        \\    changed[0]["a"]["b"].append(2)
        \\    return len(original[0]["a"]["b"]) * 10 + len(changed[0]["a"]["b"])
    ;
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, source, false));
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, source, true));
}

// spec-case: COW-NESTED-1
test "copy on write: fixed array paths retain dictionary keys and collection owners under GC stress" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\def main() -> int:
        \\    original: dict[str, [1][1]list[int]] = {"k": [[[1]]]}
        \\    changed = original
        \\    changed["k"][0][0].append(2)
        \\    return len(original["k"][0][0]) * 10 + len(changed["k"][0][0])
    ;
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, source, false));
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, source, true));
}

// spec-case: COW-NESTED-1
test "copy on write: a callback replacing an equal array entry detaches the pending receiver" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\def index(values: mut dict[str, [1]list[int]]) -> int:
        \\    copied = values["k"]
        \\    values["k"] = copied
        \\    return 0
        \\
        \\def main() -> int:
        \\    original: dict[str, [1]list[int]] = {"k": [[1]]}
        \\    changed = original
        \\    changed["k"][index(mut changed)].append(2)
        \\    return len(original["k"][0]) * 10 + len(changed["k"][0])
    ;
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(i64, 11), try run(a, source, false));
    try std.testing.expectEqual(@as(i64, 11), try run(a, source, true));
    const il = try unitText(a, source, "main", checks);
    defer a.free(il);
    try std.testing.expect(count(il, "call $myl_native_cow_scope_prepare(") == 1);
    try std.testing.expect(count(il, "call $myl_native_cow_scope_release(") > 0);
    try std.testing.expect(count(il, "extern $myl_native_cow_scope_type") == 1);
}

const fields =
    \\record Bag:
    \\    items: list[int]
    \\
    \\
    \\class Box:
    \\    items: list[int]
    \\
    \\
    \\def main() -> int:
    \\    a = Bag(items=[1])
    \\    b = a
    \\    b.items.append(2)
    \\    box = Box(items=[1])
    \\    kept = box.items
    \\    box.items.append(2)
    \\    return len(a.items) * 1000 + len(b.items) * 100 + len(kept) * 10 + len(box.items)
;

// spec-case: COW-NESTED-1
test "copy on write: a write through a record or class field writes the copy back into the field" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    const a = std.testing.allocator;
    const il = try unitText(a, fields, "main", checks);
    defer a.free(il);
    try std.testing.expect(count(il, "call $myl_native_cow_unique_in(") >= 1);
}

const pinned =
    \\def keep(xs: list[int]) -> list[list[int]]:
    \\    store: list[list[int]] = []
    \\    store.append(xs)
    \\    return store
    \\
    \\
    \\def grow(xs: mut list[int]) -> list[list[int]]:
    \\    store = keep(xs)
    \\    xs.append(9)
    \\    return store
    \\
    \\
    \\def main() -> int:
    \\    xs: list[int] = [1]
    \\    store = grow(mut xs)
    \\    return len(store[0]) * 10 + len(xs)
;

// spec: COW-PIN-1
test "copy on write: a mut argument is pinned for the call, so a callee's copy of it is a real one" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, pinned, false));
    try std.testing.expectEqual(@as(i64, 12), try run(std.testing.allocator, pinned, true));
    const a = std.testing.allocator;
    const il = try unitText(a, pinned, "main", checks);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 2), count(il, ", 1152921504606846976\n"));
    try std.testing.expectEqual(@as(usize, 2), count(il, "@unpin"));
}

// spec: COW-STATS-1
test "copy on write: a counting build counts every inline check, mark and pin and reports at exit" {
    const a = std.testing.allocator;
    const counting: Policy = .{ .step_checks = false, .frame_checks = false, .cow = .counting };
    const il = try unitText(a, pinned, "main", counting);
    defer a.free(il);
    try std.testing.expectEqual(@as(usize, 1), count(il, "call $myl_native_cow_tally(w 3)"));
    var c = try language.Compilation.init(a, "cow.my", assigned);
    defer c.deinit();
    const result = try native.runWithPolicy(&c, counting, .{});
    try std.testing.expect(!result.trapped());
    try std.testing.expectEqual(@as(i64, 23), result.value);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cow-stats {\"marks\":1,") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "\"copies\":1,") != null);
}

// spec: COW-INDEX-RETURN-1
test "copy on write: a unique mut-list element field returns without sharing" {
    const saved = value_semantics.enabled();
    value_semantics.setEnabled(true);
    defer value_semantics.setEnabled(saved);
    const source =
        \\record Payload:
        \\    number: int
        \\    items: list[int]
        \\
        \\union Item:
        \\    payload: Payload,
        \\    empty
        \\
        \\def change(items: mut list[Item], index: int):
        \\    match items[index]:
        \\        case Item.payload(old):
        \\            fields = old.items
        \\            fields.append(2)
        \\            items[index] = Item.payload(Payload(0, fields))
        \\        case Item.empty:
        \\            pass
        \\
        \\def observe(items: mut list[Item], index: int) -> int:
        \\    seen = -1
        \\    match items[index]:
        \\        case Item.payload(old):
        \\            fields = old.items
        \\            fields.append(2)
        \\            seen = len(old.items)
        \\            items[index] = Item.payload(Payload(0, fields))
        \\        case Item.empty:
        \\            pass
        \\    return seen
        \\
        \\def main() -> int:
        \\    return 0
    ;
    const a = std.testing.allocator;
    const il = try unitText(a, source, "change", checks);
    defer a.free(il);
    const negative = try unitText(a, source, "observe", checks);
    defer a.free(negative);
    try std.testing.expectEqual(@as(usize, 0), count(il, "call $myl_qbe_cow_transfer("));
    try std.testing.expect(count(negative, "call $myl_qbe_cow_transfer(") > 0);
}

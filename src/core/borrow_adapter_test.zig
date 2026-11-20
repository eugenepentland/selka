//! Borrowed physical values preserve nominal identities, equality and owners.
const std = @import("std");
const support = @import("test_support.zig");
const ir = @import("ir.zig");
const verify = @import("verify_ir.zig");

fn executes(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const run = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 42), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
}

test "O3 borrow adapters preserve nominal child identities through explicit record copies" {
    try executes(std.testing.allocator,
        \\record Coordinate:
        \\    x: int
        \\    y: int
        \\record Vec:
        \\    x: int
        \\    y: int
        \\record Named:
        \\    name: str
        \\    position: Vec
        \\func main() -> int:
        \\    const marker = Coordinate(x=10, y=20)
        \\    mut original = Named(name="owned-" + str(1), position=Vec(x=12, y=0))
        \\    const saved = copy(original)
        \\    original.position.x = 99
        \\    original.name = "changed"
        \\    if saved.name != "owned-1" or saved.position.x != 12:
        \\        return 1
        \\    return marker.x + marker.y + saved.position.x
    );
}

test "O3 borrow adapters copy nominal unions from plain and list view parameters" {
    try executes(std.testing.allocator,
        \\enum Other:
        \\    Text(value: str)
        \\    Number(value: int)
        \\enum Value:
        \\    Text(value: str)
        \\    Number(value: int)
        \\record Lookup:
        \\    value: Value
        \\    reused: bool
        \\func snapshot(value: Value) -> Value fails str:
        \\    return copy(value)
        \\func snapshots(values: Value[]) -> Value[]:
        \\    return copy(values)
        \\func lookup(value: Value) -> Lookup:
        \\    return Lookup(value=copy(value), reused=True)
        \\func main() -> int:
        \\    const other = Other.Text(value="other")
        \\    const input = Value.Text(value="payload-" + str(1))
        \\    const saved = snapshots([own input])
        \\    const found = lookup(saved[0])
        \\    match snapshot(found.value):
        \\        case Ok(value):
        \\            match value:
        \\                case Text(value=text):
        \\                    if text == "payload-1" and found.reused:
        \\                        return 42
        \\                    return 2
        \\                case Number(value=_):
        \\                    return 3
        \\        case Err(_):
        \\            return 4
    );
}

test "O3 owned wrapper copies preserve recursive boxes across callbacks and loop joins" {
    try executes(std.testing.allocator,
        \\record Node:
        \\    value: int
        \\    mapping: dict[int, int]
        \\    left: Node?
        \\func through(value: Node?) -> Node?:
        \\    return copy(value)
        \\func apply(callback: func(Node?) -> Node?, value: Node?) -> Node?:
        \\    return callback(value)
        \\func depth(value: Node?) -> int:
        \\    mut cursor = copy(value)
        \\    mut count = 0
        \\    while cursor is not None:
        \\        count += 1
        \\        cursor = copy(cursor.left)
        \\    return count
        \\func main() -> int:
        \\    mut original: Node? = Some(Node(value=7, mapping={1: 7}, left=Some(Node(value=8, mapping={2: 8}, left=None))))
        \\    mut saved = apply(through, original)
        \\    if original is None or saved is None:
        \\        return 1
        \\    original.mapping[1] = 13
        \\    original.mapping[1] = 17
        \\    if original.mapping[1] != 17 or saved.mapping[1] != 7 or depth(saved) != 2:
        \\        return 2
        \\    original.left = None
        \\    if depth(original) != 1 or depth(saved) != 2:
        \\        return 3
        \\    if apply(through, None) is not None:
        \\        return 4
        \\    return 42
    );
}

test "O3 owned wrapper copies reconstruct nested recursive box edges and every optional tag" {
    try executes(std.testing.allocator,
        \\record Node:
        \\    value: int
        \\    next: Node??
        \\func through(value: Node??) -> Node??:
        \\    return copy(value)
        \\func selected(value: Node??) -> int:
        \\    match value:
        \\        case Some(inner):
        \\            match inner:
        \\                case Some(node):
        \\                    return node.value
        \\                case None:
        \\                    return 7
        \\        case None:
        \\            return 11
        \\func main() -> int:
        \\    mut original: Node?? = Some(Some(Node(value=5, next=Some(None))))
        \\    const saved = through(original)
        \\    mut middle: Node?? = Some(None)
        \\    mut empty: Node?? = None
        \\    const copied_middle = through(middle)
        \\    const copied_empty = through(empty)
        \\    original = None
        \\    if selected(saved) != 5 or selected(copied_middle) != 7 or selected(copied_empty) != 11:
        \\        return 1
        \\    if selected(original) != 11:
        \\        return 2
        \\    return 42
    );
}

test "O3 borrow adapters compare nested views and retain projected iteration owners" {
    try executes(std.testing.allocator,
        \\record Header:
        \\    name: str
        \\    value: str
        \\func header(fields: Header[], wanted: str) -> str? from fields:
        \\    for item in fields:
        \\        if item.name == wanted:
        \\            return Some(item.value)
        \\    return None
        \\func bytes_part(value: bytes) -> bytes? from value:
        \\    return Some(value[0:2])
        \\func list_part(value: int[]) -> int[]? from value:
        \\    return Some(value[0:2])
        \\func main() -> int:
        \\    const fields = [Header(name="wanted", value="kept-" + str(7))]
        \\    const found = header(fields, "wanted")
        \\    if found != Some("kept-7") or Some("kept-7") != found:
        \\        return 1
        \\    if header(fields, "missing") is not None:
        \\        return 2
        \\    if bytes_part(b"abcd") != Some(b"ab"):
        \\        return 3
        \\    if list_part([1, 2, 3]) != Some([1, 2]):
        \\        return 4
        \\    return 42
    );
}

test "O3 borrow adapters projected list fields still require the declared argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const row = try module.intern(a, .{ .record = &.{.str} });
    const list = try module.intern(a, .{ .list_view = row });
    var b: @import("test_builder.zig").Builder = .{ .arena = a, .function = .{ .name = "projected", .signature = .{
        .params = &.{ list, list },
        .ret = .str_view,
        .borrow = .{ .sources = &.{.{ .argument = 0 }} },
    } } };
    const entry = try b.block();
    const declared = try b.detached(.{ .op = .param, .ty = list, .data = 0 });
    const undeclared = try b.detached(.{ .op = .param, .ty = list, .data = 1 });
    const zero = try b.constant(.u64, 0);
    const one = try b.constant(.u64, 1);
    const item = try b.put(entry, .{ .op = .list_get, .ty = row, .a = undeclared, .b = zero });
    const text = try b.put(entry, .{ .op = .record_get, .ty = .str, .a = item, .data = 0 });
    const view = try b.put(entry, .{ .op = .str_view_of, .ty = .str_view, .a = text, .b = zero, .data = try b.extra(&.{one}) });
    _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = view });
    try module.functions.append(a, b.function);
    var failure: verify.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, &module, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "declared argument or final owner") != null);
    try std.testing.expectError(error.Unsupported, @import("own.zig").function(a, &module, &module.functions.items[0], .{}));
    module.functions.items[0].insts.items[item.index()].a = declared;
    try verify.verifyModule(a, &module, &failure);
    _ = try @import("own.zig").function(a, &module, &module.functions.items[0], .{});
    try verify.verifyModule(a, &module, &failure);
}

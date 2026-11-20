//! Bounded ownership acceptance requires source transfers and argument loans to agree.
const std = @import("std");
const language = @import("selka");
const ownership = @import("single_owner.zig");
const report = std.debug.print;

fn accepts(parent: std.mem.Allocator, source: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "ownership-contract.selka", source);
    try unit.check();
    var failure: ownership.Failure = .{};
    ownership.check(a, unit.program.?, &failure) catch |err| {
        report("ownership contract: {s}: {s}\n", .{ failure.code, failure.message });
        return err;
    };
    return true;
}

// spec: OWNERSHIP-CONTRACT-1
test "ownership contracts allow scalar reads before an earlier mutable argument is used" {
    try std.testing.expect(try accepts(std.testing.allocator,
        \\func put(mut values: int[], index: int) -> Unit:
        \\    values[index] = 7
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    put(mut values, len(values) - 1)
        \\    return values[1]
    ));
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership contracts transfer an affine field with scalar siblings" {
    try std.testing.expect(try accepts(std.testing.allocator,
        \\resource File: filesystem
        \\record Failure:
        \\    code: int
        \\    resource: File
        \\result Finish:
        \\    ok: bool,
        \\    err: Failure
        \\func retry(own file: File) -> Finish:
        \\    match complete_resource[Finish](own file):
        \\        case ok(done):
        \\            return Ok(done)
        \\        case err(failure):
        \\            return complete_resource[Finish](own failure.resource)
        \\func main() -> int:
        \\    return 0
    ));
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership contracts allow disjoint literal mutable call arguments" {
    try std.testing.expect(try accepts(std.testing.allocator,
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut values = [[1], [2]]
        \\    const action = pair
        \\    action(mut values[0], mut values[1])
        \\    return values[0][1] + values[1][1]
    ));
}

fn deepBinaryContracts(parent: std.mem.Allocator) !bool {
    var text: std.Io.Writer.Allocating = .init(parent);
    defer text.deinit();
    try text.writer.writeAll("func main() -> int:\n    return 1");
    for (1..4096) |_| try text.writer.writeAll(" + 1");
    try text.writer.writeByte('\n');
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "deep-binary.selka", text.written());
    try unit.check();
    var program = unit.program.?;
    var failure: ownership.Failure = .{};
    try ownership.check(a, program, &failure);
    // Reverse the checked spine directly: spelling 4,096 nested parentheses
    // would test the parser's independent syntax nesting limit instead.
    const nodes = try a.dupe(language.typed.Node, program.nodes);
    for (nodes) |*node| if (node.data == .binary) {
        std.mem.swap(language.typed.NodeId, &node.data.binary.left, &node.data.binary.right);
    };
    program.nodes = nodes;
    try ownership.check(a, program, &failure);
    return true;
}

// spec-case: SEMANTIC-CACHE-7
test "ownership contracts check deep left and right binary spines without host recursion" {
    try std.testing.expect(try deepBinaryContracts(std.testing.allocator));
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership contracts binary loans cover the RHS and end before the next statement" {
    try std.testing.expect(try accepts(std.testing.allocator,
        \\func main() -> int:
        \\    mut values = [1]
        \\    const same = values == values
        \\    append(mut values, 2)
        \\    return len(values)
    ));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "binary-loan.selka",
        \\func changed(mut values: int[]) -> int[]:
        \\    append(mut values, 2)
        \\    return copy(values)
        \\func main() -> int:
        \\    mut values = [1]
        \\    const same = values == changed(mut values)
        \\    return len(values)
    );
    try unit.check();
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, unit.program.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
}

test "checkSelectedAt names the function it refuses, and only a refusal sets it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "ownership-refused-at.selka",
        \\func fine(values: int[]) -> int:
        \\    return len(values)
        \\func bad(own value: int[]) -> int:
        \\    const moved = own value
        \\    _ = value
        \\    _ = moved
        \\    return 0
        \\func main() -> int:
        \\    return 0
    );
    try unit.check();
    const program = unit.program.?;
    var failure: ownership.Failure = .{};
    var rejected: ?usize = null;
    try std.testing.expectError(error.Rejected, ownership.checkSelectedAt(a, program, &failure, null, null, &rejected));
    try std.testing.expectEqualStrings("bad", program.functions[rejected.?].name);
    // With the refused function left out of the selection nothing is refused, and the index is left as it was.
    const selection = try a.alloc(bool, program.functions.len);
    for (program.functions, selection) |function, *slot| slot.* = !std.mem.eql(u8, function.name, "bad");
    var other: ?usize = null;
    try ownership.checkSelectedAt(a, program, &failure, selection, null, &other);
    try std.testing.expectEqual(@as(?usize, null), other);
}

//! Borrowed `const` (B9): `const name = place` binds a read-only borrow of a
//! parameter, an element, a field or a dictionary value of a parameter or a local owner. The owner cannot change or move
//! while the binding is live. An owning use needs an explicit transfer or copy;
//! a declared `from` return reads the binding as a borrow.
const std = @import("std");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const language = @import("selka");

/// Require ordinary typing to pass, then pin the actual Core ownership refusal and rule.
fn expectRefusal(allocator: std.mem.Allocator, text: []const u8, expected: language.ownership_rules.Refusal) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
}

/// Check `text` and require that it is accepted by sema and by the ownership checker.
fn expectAccepted(allocator: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure);
}

test "R1: a const of a parameter's element, field or dictionary value, and of a local owner's, is accepted" {
    try expectAccepted(std.testing.allocator,
        \\record Holder:
        \\    items: int[]
        \\func element(rows: int[][]) -> int:
        \\    const row = rows[1]
        \\    return len(row)
        \\func field(h: Holder) -> int:
        \\    const items = h.items
        \\    return len(items)
        \\func value(d: dict[str, int[]]) -> int:
        \\    const v = d["a"]
        \\    return len(v)
        \\func whole(xs: int[]) -> int:
        \\    const ys = xs
        \\    return len(ys)
        \\func main(out: Stream) -> int:
        \\    mut local = [[1, 2], [3, 4, 5]]
        \\    const inner = local[1]
        \\    mut holder = Holder(items=[1, 2, 3])
        \\    const kept = holder.items
        \\    print(out, element(local) + field(holder) + value({"a": [7]}) + whole([9]) + len(inner) + len(kept))
        \\    return 0
    );
}

test "R1: a change of the owner after the binding's last use is accepted" {
    try expectAccepted(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3, 4, 5]]
        \\    const row = rows[1]
        \\    print(out, len(row))
        \\    append(mut rows, [6])
        \\    return 0
    );
}

test "R1: a change of the owner while the binding is live is refused with the overlap code" {
    try expectRefusal(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3, 4, 5]]
        \\    const row = rows[1]
        \\    append(mut rows, [6])
        \\    print(out, len(row))
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
}

test "R1: a change of a parameter's owner in a branch before the binding's use is refused" {
    try expectRefusal(std.testing.allocator,
        \\func total(mut rows: int[][], flag: bool) -> int:
        \\    const row = rows[1]
        \\    if flag:
        \\        append(mut rows, [6])
        \\    return len(row)
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3, 4, 5]]
        \\    print(out, total(mut rows, True))
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
}

test "R1: a move of a local owner while the binding is live is refused with the overlap code" {
    try expectRefusal(std.testing.allocator,
        \\record Holder:
        \\    items: int[]
        \\func main(out: Stream) -> int:
        \\    mut holder = Holder(items=[1, 2, 3])
        \\    const items = holder.items
        \\    const moved = own holder
        \\    print(out, len(items) + len(moved.items))
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
}

test "B9: aliases of borrowed siblings can be read but an owning store is refused" {
    const source =
        \\func main(out: Stream) -> int:
        \\    mut rows = [["a"], ["bb"]]
        \\    const first = rows[0]
        \\    const second = rows[1]
        \\    const kept = first
        \\    print(out, len(kept) + len(second))
        \\    return 0
    ;
    try expectAccepted(std.testing.allocator, source);
    // A `mut` binding stored once from the alias borrows it too (D4); a write through it is the refusal.
    const stored = try std.mem.replaceOwned(u8, std.testing.allocator, source, "const kept = first", "mut kept = first");
    defer std.testing.allocator.free(stored);
    try expectAccepted(std.testing.allocator, stored);
    const written = try std.mem.replaceOwned(u8, std.testing.allocator, source, "const kept = first", "mut kept = first\n    append(mut kept, \"c\")");
    defer std.testing.allocator.free(written);
    try expectRefusal(std.testing.allocator, written, .{ .code = "E_OWN_MARKER", .rule = .B9 });
}

test "R1: a binding is refused when it is stored, returned or passed to an owned parameter" {
    // R3b: a const element of a list parameter returned onward is an accepted borrow (see borrowed_return_test.zig).
    try expectRefusal(std.testing.allocator,
        \\func my_take(own xs: int[]) -> int:
        \\    return len(xs)
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3, 4, 5]]
        \\    const row = rows[1]
        \\    print(out, my_take(own row))
        \\    return 0
    , .{ .code = "E_OWN_MARKER", .rule = .B9 });
    try expectRefusal(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3, 4, 5]]
        \\    const row = rows[1]
        \\    mut kept = row
        \\    append(mut kept, 6)
        \\    print(out, len(kept))
        \\    return 0
    , .{ .code = "E_OWN_MARKER", .rule = .B9 });
}

test "R1: a mut binding of a place stored once borrows it while read, and a write through it is refused (D4)" {
    try expectAccepted(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3, 4, 5]]
        \\    mut row = rows[1]
        \\    print(out, len(row))
        \\    return 0
    );
    try expectRefusal(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1, 2], [3, 4, 5]]
        \\    mut row = rows[1]
        \\    append(mut row, 6)
        \\    print(out, len(row))
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B7 });
}

/// The first refusal code `text` fails with, the sema diagnostic or the ownership refusal; `allocator` owns the result.
fn refusalCode(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    if (!unit.passed) {
        try std.testing.expectEqualStrings("E_IMMUTABLE", unit.diagnostics[0].code);
        return allocator.dupe(u8, unit.diagnostics[0].code);
    }
    var failure: contract.Failure = .{};
    const checked = contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure);
    if (checked) |_| return allocator.dupe(u8, "accepted") else |err| {
        try std.testing.expectEqual(error.Rejected, err);
        return allocator.dupe(u8, failure.code);
    }
}

/// Check every refused cell of the generated matrix: each file is refused with one of the codes its manifest line
/// names. Returns how many cells were checked.
fn checkManifest(allocator: std.mem.Allocator) !usize {
    const manifest = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/borrowed_const/manifest.txt", allocator, .limited(1 << 20));
    defer allocator.free(manifest);
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "refused ")) continue;
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        _ = fields.next();
        const cell = fields.next() orelse return error.TestUnexpectedResult;
        const path = try std.fmt.allocPrint(allocator, "tests/borrowed_const/refused/{s}.selka", .{cell});
        defer allocator.free(path);
        const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(1 << 20));
        defer allocator.free(source);
        const got = try refusalCode(allocator, source);
        defer allocator.free(got);
        var matched = false;
        while (fields.next()) |code| {
            if (std.mem.eql(u8, code, got)) matched = true;
        }
        if (!matched) try std.testing.expectEqualStrings(line["refused ".len..], got);
        checked += 1;
    }
    return checked;
}

test "R1: every refused cell of the borrowed-const matrix is refused with its manifest code" {
    const checked = try checkManifest(std.testing.allocator);
    try std.testing.expect(checked > 0);
}

test "R1: the borrowed-const matrix is current" {
    // The generator is the source of truth: regenerate in memory and compare with the committed cells.
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{ "python3", "tests/borrowed_const/matrix.py", "--check" },
    });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "is current") != null);
}

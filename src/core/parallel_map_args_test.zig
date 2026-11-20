//! The trailing arguments of `parallel.map` (E1c): a managed argument is lent to every item, and a slice or a borrowed text,
//! bytes or list parameter is lent as the view itself, with no copy (FR59). A list element is bound first (E_TASK_LOAN),
//! and a `mut` argument is refused (E_TASK_MUT). The accepted forms check and pass the same ownership pass as the refused ones.
const std = @import("std");
const build = @import("build.zig");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const language = @import("selka");

/// Check `text`: the sema diagnostic it fails with, or the ownership refusal (with the entry source, so `parallel.map` is
/// identified). The first code it fails with must be `code`.
fn expectRefusal(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    if (!unit.passed) return std.testing.expectEqualStrings(code, unit.diagnostics[0].code);
    var failure: contract.Failure = .{};
    contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure) catch |err| {
        try std.testing.expectEqual(error.Rejected, err);
        return std.testing.expectEqualStrings(code, failure.code);
    };
    try std.testing.expectEqualStrings(code, "accepted");
}

/// Check `text` and require that it is accepted by the checker and the ownership pass.
fn expectAccepted(allocator: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure);
}

// FR59 (decision PARMAP, 17 November 2026): a view bound from a call, a slice, and a plain text, bytes or list parameter
// are lent to every item as the view itself, so none is refused (K3 at `parallel.map` was lifted); copy(...) is accepted too.
test "parallel map arguments: a call-derived view, a slice and a plain text, bytes or list parameter are accepted" {
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func head(text: str) -> str from text:
        \\    return text[0:1]
        \\func add(value: int, text: str) -> int:
        \\    return value + len(text)
        \\func total(text: str) -> int:
        \\    const piece = head(text)
        \\    return parallel.map([1], add, piece)[0]
        \\func main() -> int:
        \\    return total("abc")
    );
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func f(value: int, names: str[]) -> int:
        \\    return value + len(names)
        \\func main(out: Stream) -> int:
        \\    mut items: int[] = []
        \\    append(mut items, 1)
        \\    mut names: str[] = []
        \\    append(mut names, "a")
        \\    print(out, parallel.map(items, f, names[0:1])[0])
        \\    return 0
    );
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func f(value: int, names: str[]) -> int:
        \\    return value + len(names)
        \\func total(names: str[]) -> int:
        \\    mut items: int[] = []
        \\    append(mut items, 1)
        \\    return parallel.map(items, f, names)[0]
        \\func main(out: Stream) -> int:
        \\    mut names: str[] = []
        \\    append(mut names, "a")
        \\    print(out, total(names))
        \\    return 0
    );
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func g(value: int, label: str) -> int:
        \\    return value + len(label)
        \\func total(label: str) -> int:
        \\    mut items: int[] = []
        \\    append(mut items, 1)
        \\    return parallel.map(items, g, label)[0]
        \\func main(out: Stream) -> int:
        \\    print(out, total("abc"))
        \\    return 0
    );
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func g(value: int, data: bytes) -> int:
        \\    return value + len(data)
        \\func total(data: bytes) -> int:
        \\    mut items: int[] = []
        \\    append(mut items, 1)
        \\    return parallel.map(items, g, data)[0]
        \\func main(out: Stream) -> int:
        \\    print(out, total(bytes([1, 2])))
        \\    return 0
    );
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func g(value: int, label: str) -> int:
        \\    return value + len(label)
        \\func total(label: str) -> int:
        \\    mut items: int[] = []
        \\    append(mut items, 1)
        \\    return parallel.map(items, g, copy(label))[0]
        \\func main(out: Stream) -> int:
        \\    const data = bytes([1, 2])
        \\    print(out, total("abc"), parallel.map([1], g, "x")[0])
        \\    return 0
    );
}

test "parallel map arguments: a list element and a mut argument are refused at the argument" {
    try expectRefusal(std.testing.allocator,
        \\import parallel
        \\record Row:
        \\    cells: int[]
        \\func g(value: int, row: Row) -> int:
        \\    return value + len(row.cells)
        \\func main(out: Stream) -> int:
        \\    mut items: int[] = []
        \\    append(mut items, 1)
        \\    mut rows: Row[] = []
        \\    append(mut rows, Row(cells=[1, 2]))
        \\    print(out, parallel.map(items, g, rows[0])[0])
        \\    return 0
        \\
    , "E_TASK_LOAN");
    try expectRefusal(std.testing.allocator,
        \\import parallel
        \\func g(value: int, names: str[]) -> int:
        \\    return value + len(names)
        \\func main(out: Stream) -> int:
        \\    mut items: int[] = []
        \\    append(mut items, 1)
        \\    mut names: str[] = []
        \\    print(out, parallel.map(items, g, mut names)[0])
        \\    return 0
    , "E_TASK_MUT");
}

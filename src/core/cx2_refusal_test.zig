//! Lane CX2's refusals: a list slice or a borrowed list parameter may not reach an owned position without a spelled
//! copy (R-B4; R-B2 at `parallel.map` was lifted by FR59); a `mut` argument cannot be a list view (R-B3); a buffer is
//! not written from its own octets without `bytes(buf)` (R-B17).
const std = @import("std");
const ir = @import("ir.zig");
const build = @import("build.zig");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const verify_ir = @import("verify_ir.zig");

/// Check `text`: the sema diagnostic it fails with, or the ownership refusal (with the entry source, so
/// `parallel.map` is identified). The first code it fails with must be `code`.
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
    // Accepted, where a refusal was required: this fails with the expected code in the message.
    try std.testing.expectEqualStrings(code, "accepted");
}

/// Check `text` and require that it is accepted.
fn expectAccepted(allocator: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), text);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try contract.checkWithSource(arena.allocator(), unit.program.?, unit.src.?, &failure);
}

test "CX2 R-B4: a list slice passed to an owned parameter is refused with the copy repair, and copy(...) is accepted" {
    try expectRefusal(std.testing.allocator,
        // migrate-embedded: skip original owned-argument or parallel-view refusal and copy-repair witness
        \\func my_take(own xs: int[]) -> int:
        \\    return len(xs)
        \\func main(out: Stream) -> int:
        \\    const data = [1, 2, 3, 4]
        \\    print(out, my_take(data[1:3]))
        \\    return 0
    , "E_SLICE_ESCAPES");
    try expectAccepted(std.testing.allocator,
        \\func my_take(own xs: int[]) -> int:
        \\    return len(xs)
        \\func main(out: Stream) -> int:
        \\    const data = [1, 2, 3, 4]
        \\    print(out, my_take(copy(data[1:3])))
        \\    return 0
    );
}

// FR59 (decision PARMAP, 17 November 2026): `parallel.map` lends a slice or a borrowed list parameter as the view itself,
// with no copy, so R-B2 no longer refuses either; a spelled copy is still accepted.
test "CX2 R-B2 lifted: parallel.map over a slice or over a borrowed list parameter is accepted, as is copy(...)" {
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func double(x: int) -> int:
        \\    return x * 2
        \\func main(out: Stream) -> int:
        \\    const data = [1, 2, 3, 4]
        \\    print(out, len(parallel.map(data[1:3], double)))
        \\    return 0
    );
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func double(x: int) -> int:
        \\    return x * 2
        \\func total(xs: int[]) -> int:
        \\    return len(parallel.map(xs, double))
        \\func main(out: Stream) -> int:
        \\    print(out, total([1, 2, 3, 4]))
        \\    return 0
    );
    try expectAccepted(std.testing.allocator,
        \\import parallel
        \\func double(x: int) -> int:
        \\    return x * 2
        \\func total(xs: int[]) -> int:
        \\    return len(parallel.map(copy(xs), double))
        \\func main(out: Stream) -> int:
        \\    const data = [1, 2, 3, 4]
        \\    print(out, total(data) + len(parallel.map(data, double)))
        \\    return 0
    );
}

test "CX2 R-B3: a mut argument cannot be a list view: a parameter, a slice and a view binding are refused at check time" {
    try expectRefusal(std.testing.allocator,
        \\func bump(mut xs: int[]) -> int:
        \\    xs[0] = 9
        \\    return len(xs)
        \\func g(xs: int[]) -> int:
        \\    return bump(mut xs)
        \\func main() -> int:
        \\    return g([1, 2])
    , "E_IMMUTABLE");
    try expectRefusal(std.testing.allocator,
        \\func bump(mut xs: int[]) -> int:
        \\    xs[0] = 9
        \\    return len(xs)
        \\func main() -> int:
        \\    const data = [1, 2, 3, 4]
        \\    return bump(mut data[1:3])
    , "E_MUTATION_MARKER");
    try expectRefusal(std.testing.allocator,
        \\func bump(mut xs: int[]) -> int:
        \\    xs[0] = 9
        \\    return len(xs)
        \\func main() -> int:
        \\    const data = [1, 2, 3, 4]
        \\    const part = data[1:3]
        \\    return bump(mut part)
    , "E_IMMUTABLE");
}

test "CX2 R-B17: a buffer written from its own octets is refused, and bytes(buf) is accepted" {
    try expectRefusal(std.testing.allocator,
        \\import buffers
        \\func main(out: Stream) -> int:
        \\    mut buf = byte_buffer([65, 66, 67])
        \\    _ = buffers.append_range(mut buf, buf, 0, 2)
        \\    print(out, len(buf))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try expectAccepted(std.testing.allocator,
        \\import buffers
        \\func main(out: Stream) -> int:
        \\    mut buf = byte_buffer([65, 66, 67])
        \\    _ = buffers.append_range(mut buf, bytes(buf), 0, 2)
        \\    print(out, len(buf))
        \\    return 0
    );
}

/// The `myl_core_view_copy_bytes` calls in the functions named `suffix` (the copies a bytes view makes for an owned use).
fn viewCopiesIn(module: *const ir.Module, suffix: []const u8) usize {
    var count: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.endsWith(u8, function.name, suffix)) continue;
        for (function.insts.items) |inst| {
            if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_view_copy_bytes")) count += 1;
        }
    }
    return count;
}

test "CX2: a bytes view default of dicts.get selects a borrowed view, so a read copies nothing and a copy copies once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a,
        \\import dicts
        \\func read_only(table: dict[str, bytes], key: str, net: bytes) -> int:
        \\    return len(dicts.get(table, key, net))
        \\func copying(table: dict[str, bytes], key: str, net: bytes) -> bytes:
        \\    return copy(dicts.get(table, key, net))
        \\func main(out: Stream) -> int:
        \\    const table: dict[str, bytes] = {"net": b"found"}
        \\    print(out, read_only(table, "net", b"x"), len(copying(table, "no", b"xy")))
        \\    return 0
    );
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
    var failure: verify_ir.Failure = .{};
    try verify_ir.verifyModule(a, &module, &failure);
    try std.testing.expectEqual(@as(usize, 0), viewCopiesIn(&module, "read_only"));
    try std.testing.expectEqual(@as(usize, 1), viewCopiesIn(&module, "copying"));
}

/// The view materializations in the functions named `suffix` after the passes: a `str_from_view` and a bytes view copy.
fn materializationsIn(module: *const ir.Module, suffix: []const u8) usize {
    var count: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.endsWith(u8, function.name, suffix)) continue;
        for (function.insts.items) |inst| {
            if (inst.op == .str_from_view) count += 1;
            if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_view_copy_bytes")) count += 1;
        }
    }
    return count;
}

test "CX2: a text view needle, a whitespace split of a text view and a bytes view key are read in place after the passes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a,
        \\import strings
        \\
        \\func members(text: str, needle: str) -> bool:
        \\    return needle in text
        \\func words(text: str) -> int:
        \\    mut total = 0
        \\    for word in strings.words(text):
        \\        total += len(word)
        \\    return total
        \\func probe(keys: dict[bytes, int], a: bytes) -> int:
        \\    return keys[a[1:4]]
        \\func main(out: Stream) -> int:
        \\    print(out, members("hello", "ell"), words("a bb"), probe({b"bcd": 7}, b"abcdef"))
        \\    return 0
    );
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
    _ = try support.runPasses(a, &module, .trusted);
    try std.testing.expectEqual(@as(usize, 0), materializationsIn(&module, "members"));
    try std.testing.expectEqual(@as(usize, 0), materializationsIn(&module, "words"));
    try std.testing.expectEqual(@as(usize, 0), materializationsIn(&module, "probe"));
}

//! 4c: a literal default of `unwrap_or` or `dicts.get` is a static constant, so the selection borrows only its option or
//! dictionary. The empty list `[]` is one too since 4e (the lowering's static empty list). The neighbours stay refused: a change of that owner while a borrow of the selection is live, a return
//! without `from`, a store of the selection into owning storage, and a default that is not a literal (its owner must be
//! declared too). Guest behaviour is `tests/lang/unwrap_or_defaults.selka`.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    if (!std.mem.eql(u8, code, failure.code)) report("unexpected refusal: {s} {s}\n", .{ failure.code, failure.message });
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
}

fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    unique.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
        report("refused: {s} {s}\n", .{ failure.code, failure.message });
        return err;
    };
    try std.testing.expectEqualStrings("", failure.code);
}

test "4c a literal default borrows only its option, so a from accessor returns it" {
    try accepts(std.testing.allocator,
        \\record R:
        \\    name: bytes?
        \\
        \\func name_of(r: R) -> bytes from r:
        \\    return r.name.unwrap_or(b"")
        \\
        \\func main() -> int:
        \\    return len(name_of(R(name=None)))
        \\
    );
}

test "4c the option's owner stays held while a borrow of a literal-default selection is live" {
    try refuses(std.testing.allocator,
        \\record R:
        \\    name: bytes?
        \\
        \\func main() -> int:
        \\    mut r = R(name=Some(b"abc"))
        \\    const n = r.name.unwrap_or(b"")
        \\    r.name = None
        \\    return len(n)
        \\
    , "E_SINGLE_OWNER_OVERLAP");
}

test "4c a literal-default selection still needs from to return and copy to store" {
    try refuses(std.testing.allocator,
        \\record R:
        \\    name: bytes?
        \\
        \\func name_of(r: R) -> bytes:
        \\    return r.name.unwrap_or(b"")
        \\
        \\func main() -> int:
        \\    return len(name_of(R(name=None)))
        \\
    , "E_BORROW_UNDECLARED");
    try refuses(std.testing.allocator,
        \\record R:
        \\    name: bytes?
        \\
        \\func keep(r: R) -> bytes[]:
        \\    mut out: bytes[] = []
        \\    append(mut out, r.name.unwrap_or(b""))
        \\    return out
        \\
        \\func main() -> int:
        \\    return len(keep(R(name=None)))
        \\
    , "E_SINGLE_OWNER_BORROW");
}

test "4c a default that is not a literal keeps its owner" {
    try refuses(std.testing.allocator,
        \\record R:
        \\    name: bytes?
        \\
        \\func name_of(r: R, fallback: bytes) -> bytes from r:
        \\    return r.name.unwrap_or(fallback)
        \\
        \\func main() -> int:
        \\    return len(name_of(R(name=None), b"x"))
        \\
    , "E_BORROW_UNDECLARED");
}

test "4c with 4e: an empty list default is static, so unwrap_or([]) and dicts.get(d, k, []) return under from" {
    try accepts(std.testing.allocator,
        \\import dicts
        \\
        \\record R:
        \\    names: str[]?
        \\
        \\func names_of(r: R) -> str[] from r:
        \\    return r.names.unwrap_or([])
        \\
        \\func row(d: dict[str, int[]], k: str) -> int[] from d:
        \\    return dicts.get(d, k, [])
        \\
        \\func main() -> int:
        \\    return len(names_of(R(names=None))) + len(row({"a": [1]}, "b"))
        \\
    );
}

test "4c with 4e: a list default with elements, or a named empty list, keeps its owner" {
    try refuses(std.testing.allocator,
        \\record R:
        \\    names: str[]?
        \\
        \\func names_of(r: R) -> str[] from r:
        \\    return r.names.unwrap_or(["none"])
        \\
        \\func main() -> int:
        \\    return len(names_of(R(names=None)))
        \\
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\record R:
        \\    names: str[]?
        \\
        \\func names_of(r: R, fallback: str[]) -> str[] from r:
        \\    return r.names.unwrap_or(fallback)
        \\
        \\func main() -> int:
        \\    return len(names_of(R(names=None), []))
        \\
    , "E_BORROW_UNDECLARED");
}

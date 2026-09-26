//! Standalone named constraints share the module declaration namespace.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const constraint_lookup = @import("constraint_lookup.zig");

fn reject(bytes: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "namespace-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expect(c.diagnostics.items.len != 0);
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

fn accept(bytes: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "namespace-valid.my", bytes);
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
}

// spec: NAMED-CONSTRAINT-NAMESPACE-1
test "standalone named constraints namespace rejects duplicate declarations used and unused" {
    try reject(
        \\constraint C[T] = copy
        \\constraint C[T] = equality
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\constraint C[T] = copy
        \\constraint C[T] = integer
        \\def identity[T: C](x: T) -> T:
        \\    return x
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
}

// spec: NAMED-CONSTRAINT-NAMESPACE-2
test "standalone named constraints namespace rejects nominal and function collisions" {
    try reject(
        \\record C:
        \\    value: int
        \\constraint C[T] = copy
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\constraint C[T] = copy
        \\record C:
        \\    value: int
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\constraint C[T] = copy
        \\union C:
        \\    item: int
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\constraint C[T] = copy
        \\domain C: int:
        \\    pass
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\constraint C[T] = copy
        \\resource C: int;
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\constraint C[T] = copy
        \\type C = int
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\constraint C[T] = copy
        \\def C[T](x: T) -> T:
        \\    return x
        \\def main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
}

// spec: NAMED-CONSTRAINT-NAMESPACE-3
test "standalone named constraints namespace lookup rejects duplicate matches" {
    var c = try language.Compilation.init(t.allocator, "namespace-lookup.my",
        \\constraint C[T] = copy
        \\constraint C[T] = integer
    );
    defer c.deinit();
    try c.parse();
    try t.expectEqual(@as(usize, 2), c.syntax.?.types.constraints.len);
    var provider: constraint_lookup.Provider = .{ .program = c.syntax.?, .src = c.src };
    var sink: diagnostic.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    const reference: ast.BoundReference = .{ .alias = null, .name = c.syntax.?.types.constraints[0].name };
    const lookup = provider.lookup();
    try t.expectError(error.SourceError, lookup.find(lookup.ctx, reference, &sink));
    try t.expectEqualStrings("E_DUPLICATE_SYMBOL", sink.items.items[0].code);
}

// spec: NAMED-CONSTRAINT-NAMESPACE-4
test "standalone named constraints namespace accepts unused and multi-constraint programs" {
    try accept(
        \\constraint Unused[T] = copy
        \\def main() -> int:
        \\    return 0
    );
    try accept(
        \\constraint HasValue[T] = copy + field(value: int)
        \\constraint HasTag[T] = copy + field(tag: bool)
        \\def read[T: HasValue + HasTag](x: T) -> int:
        \\    return x.value
        \\def main() -> int:
        \\    return 0
    );
}

// spec: NAMED-CONSTRAINT-SUBJECT-1
test "standalone named constraints reject subject shadowing before use" {
    try reject(
        \\record Item:
        \\    value: int
        \\constraint C[Item] = copy
        \\def main() -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\constraint C[Item] = copy
        \\record Item:
        \\    value: int
        \\def use[T: C](item: T) -> T:
        \\    return item
        \\def main() -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\constraint C[helper] = copy
        \\def helper() -> int:
        \\    return 1
        \\def main() -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\type Item = int
        \\constraint C[Item] = copy
    , "E_SHADOWING");
    try reject(
        \\constraint C[T] = copy
        \\constraint Other[C] = copy
    , "E_SHADOWING");
    try reject(
        \\constraint C[int] = copy
    , "E_GENERIC_PARAMETER");
    try accept(
        \\constraint First[T] = copy
        \\constraint Second[T] = equality
        \\def main() -> int:
        \\    return 0
    );
}

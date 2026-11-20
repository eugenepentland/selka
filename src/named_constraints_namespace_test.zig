//! Standalone named constraints share the module declaration namespace.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const constraint_lookup = @import("constraint_lookup.zig");

fn reject(bytes: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "namespace-invalid.selka", bytes);
    defer c.deinit();
    try expectSourceError(c.check());
    try t.expect(c.diagnostics.items.len != 0);
    try t.expect(hasCode(c.diagnostics.items, code));
}

fn accept(bytes: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "namespace-valid.selka", bytes);
    defer c.deinit();
    try expectSourceError(c.check());
    try t.expect(hasCode(c.diagnostics.items, "E_DOMAIN_REMOVED"));
}

// spec: NAMED-CONSTRAINT-NAMESPACE-1
test "standalone named constraints namespace rejects duplicate declarations used and unused" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\constraint C[T] = equality
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\constraint C[T] = integer
        \\func identity[T: C](x: T) -> T:
        \\    return x
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
}

// spec: NAMED-CONSTRAINT-NAMESPACE-2
test "standalone named constraints namespace rejects nominal and function collisions" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\record C:
        \\    value: int
        \\constraint C[T] = copy
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\record C:
        \\    value: int
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\enum C:
        \\    item(value: int)
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\domain C: int:
        \\    pass
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\resource C: int
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\type C = int
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\func C[T](x: T) -> T:
        \\    return x
        \\func main() -> int:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
}

// spec: NAMED-CONSTRAINT-NAMESPACE-3
test "standalone named constraints namespace lookup rejects duplicate matches" {
    var c = try language.Compilation.init(t.allocator, "namespace-lookup.selka",
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
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
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Unused[T] = copy
        \\func main() -> int:
        \\    return 0
    );
    try accept(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint HasValue[T] = copy + field(value: int)
        \\constraint HasTag[T] = copy + field(tag: bool)
        \\func read[T: HasValue + HasTag](x: T) -> int:
        \\    return x.value
        \\func main() -> int:
        \\    return 0
    );
}

// spec: NAMED-CONSTRAINT-SUBJECT-1
test "standalone named constraints reject subject shadowing before use" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\record Item:
        \\    value: int
        \\constraint C[Item] = copy
        \\func main() -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[Item] = copy
        \\record Item:
        \\    value: int
        \\func use[T: C](item: T) -> T:
        \\    return item
        \\func main() -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[helper] = copy
        \\func helper() -> int:
        \\    return 1
        \\func main() -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\type Item = int
        \\constraint C[Item] = copy
    , "E_SHADOWING");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[T] = copy
        \\constraint Other[C] = copy
    , "E_SHADOWING");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint C[int] = copy
    , "E_GENERIC_PARAMETER");
    try accept(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint First[T] = copy
        \\constraint Second[T] = equality
        \\func main() -> int:
        \\    return 0
    );
}

fn hasCode(items: anytype, code: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.code, code)) return true;
    return false;
}

fn expectSourceError(outcome: anyerror!void) anyerror!void {
    outcome catch |err| {
        if (err == error.SourceError) return;
        return err;
    };
    return error.TestExpectedError;
}

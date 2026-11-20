//! `copy(value)` is the one copy spelling: the prelude call copies any
//! copyable value, the method is refused with its certain rewrite, and a
//! resource keeps its own refusal.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const copy_method = @import("copy_method.zig");

/// Check a program that must be accepted.
fn accepted(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "copy.selka", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

/// Check a program that must be rejected with `code` and exactly `message`.
fn expectRejected(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "copy.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expectEqualStrings(message, compilation.diagnostics.items[0].message);
}

/// Copy the replacement text of the first diagnostic's repair into `buffer`.
fn fixText(buffer: []u8, text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "copy.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const fix = compilation.diagnostics.items[0].provenance.fix orelse return "";
    try t.expect(fix.edit.text.len <= buffer.len);
    @memcpy(buffer[0..fix.edit.text.len], fix.edit.text);
    return buffer[0..fix.edit.text.len];
}

// spec: COPY-CALL-1
test "copy is a prelude call over any copyable value" {
    try accepted(
        \\record Pair:
        \\    text: str
        \\    count: int
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    mut ys = copy(xs)
        \\    mut pair = copy(Pair(text="a", count=1))
        \\    mut number = copy(3)
        \\    append(mut ys, 4)
        \\    return len(xs) * 100 + len(ys) * 10 + pair.count + number
    );
}

// spec: COPY-CALL-1
test "copy takes exactly one value" {
    try expectRejected(
        \\func main() -> int:
        \\    return copy()
    , "E_ARITY", "copy takes one value: `copy(value)`");
    try expectRejected(
        \\func main() -> int:
        \\    return copy(1, 2)
    , "E_ARITY", "copy takes one value: `copy(value)`");
}

// spec: COPY-METHOD-1
test "the copy method is refused with the prelude call" {
    try expectRejected(
        // migrate-embedded: skip original copy-method refusal and exact prelude-repair witness
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    mut ys = xs.copy()
        \\    return len(ys)
    , copy_method.code, copy_method.message);
    try expectRejected(
        // migrate-embedded: skip original copy-method refusal and exact prelude-repair witness
        \\func main() -> int:
        \\    return len(copy_list([1, 2]).copy())
        \\
        \\
        \\func copy_list(values: int[]) -> int[]:
        \\    return values
    , copy_method.code, copy_method.message);
}

// spec: COPY-METHOD-1
test "the method repair names the prelude call over the receiver text" {
    var buffer: [64]u8 = undefined;
    try t.expectEqualStrings("copy(xs)", try fixText(&buffer,
        // migrate-embedded: skip original copy-method refusal and exact prelude-repair witness
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    mut ys = xs.copy()
        \\    return len(ys)
    ));
    try t.expectEqualStrings("copy(values[0])", try fixText(&buffer,
        // migrate-embedded: skip original copy-method refusal and exact prelude-repair witness
        \\func main() -> int:
        \\    mut values = [[1], [2]]
        \\    mut first = values[0].copy()
        \\    return len(first)
    ));
}

// spec: COPY-METHOD-1
test "a move-only resource keeps its copy refusal and a capability copies (5C)" {
    try expectRejected(
        \\resource Ticket: filesystem
        \\func keep(own ticket: Ticket) -> int:
        \\    mut copied = ticket.copy()
        \\    return 0
        \\
        \\func main() -> int:
        \\    return 0
    , "E_COLLECTION_METHOD", "resource and move-only values cannot be copied");
    // A capability is a shareable handle (5C): `copy(fs)` is the handle itself.
    try accepted(
        \\func main(fs: Filesystem) -> int:
        \\    const copy_of_fs = copy(fs)
        \\    if copy_of_fs.exists("x"):
        \\        return 1
        \\    return 0
    );
    // A copy of a literal is accepted; the checker advises dropping it (`W_NEEDLESS_COPY`), a warning and not a refusal.
    var literal = try language.Compilation.init(t.allocator, "copy.selka", "func main() -> int:\n    mut data = copy(b\"abc\")\n    return len(data)\n");
    defer literal.deinit();
    try literal.check();
    for (literal.diagnostics.items) |item| try t.expectEqual(language.diagnostic.Severity.warning, item.severity);
}

// spec: COPY-CALL-1
test "a generic body copies its parameter" {
    try accepted(
        \\func duplicate[T: copy + storable](value: T) -> T[]:
        \\    mut out: T[] = []
        \\    append(mut out, copy(value))
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    return len(duplicate(7))
    );
}

// spec: FIX-MIGRATION-CAPTURE-1
test "the copy rewrite survives a try and stays withheld for a declared copy" {
    var buffer: [32]u8 = undefined;
    try t.expectEqualStrings("copy(items)", try fixText(&buffer,
        // migrate-embedded: skip original copy-method refusal and exact prelude-repair witness
        \\func first_value(items: int[]?) -> int?:
        \\    mut present = try items.copy()
        \\    return Some(len(present))
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ));
    var declared = try language.Compilation.init(t.allocator, "copy.selka",
        \\func copy(value: int) -> int:
        \\    return value
        \\
        \\
        \\func pick(items: int[]) -> int:
        \\    mut present = items.copy()
        \\    return len(present)
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer declared.deinit();
    try t.expectError(error.SourceError, declared.check());
    try t.expectEqualStrings(copy_method.code, declared.diagnostics.items[0].code);
    try t.expect(declared.diagnostics.items[0].provenance.fix == null);
}

test "F6 copy proof name claims distinguish requirements and expressions from bindings" {
    try t.expect(!try language.lexer.claimsName(t.allocator, "func count[T: copy + storable](value: T):\n    return\n", "copy"));
    try t.expect(!try language.lexer.claimsName(t.allocator, "func count[T: storable + copy](value: T):\n    return\n", "copy"));
    try t.expect(!try language.lexer.claimsName(t.allocator, "func count[T: storable +\n    copy](value: T):\n    return\n", "copy"));
    try t.expect(!try language.lexer.claimsName(t.allocator, "const value = copy(other)\n", "copy"));
    try t.expect(try language.lexer.claimsName(t.allocator, "func copy(value: int) -> int:\n    return value\n", "copy"));
    try t.expect(try language.lexer.claimsName(t.allocator, "const copy = operation\n", "copy"));
    try t.expect(try language.lexer.claimsName(t.allocator, "func count(copy: int) -> int:\n    return copy\n", "copy"));
    try t.expect(try language.lexer.claimsName(t.allocator, "import original as copy\n", "copy"));
    try t.expect(try language.lexer.claimsName(t.allocator, "if True:\n    copy = operation\n", "copy"));
}

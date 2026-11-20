//! The removed integer bit operators: `&`, `|` and `^` name the prelude
//! operation they spell, and the set operators stay a set's own spelling.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const bit_operators = @import("bit_operators.zig");

/// Check a program that must be accepted.
fn accepted(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bits.selka", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

/// Check a program that must be rejected with `code` and exactly `message`.
fn expectRejected(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bits.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expectEqualStrings(message, compilation.diagnostics.items[0].message);
}

/// Copy the replacement text of the first diagnostic's repair into `buffer`.
fn fixText(buffer: []u8, text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "bits.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const fix = compilation.diagnostics.items[0].provenance.fix orelse return "";
    try t.expect(fix.edit.text.len <= buffer.len);
    @memcpy(buffer[0..fix.edit.text.len], fix.edit.text);
    return buffer[0..fix.edit.text.len];
}

// spec: BIT-OPERATORS-1
test "the prelude operations combine two integers" {
    try accepted(
        \\func main() -> int:
        \\    mut flags: u8 = 12u8
        \\    return int(bit_and(flags, 10u8)) + int(bit_or(flags, 10u8)) + int(bit_xor(flags, 10u8))
    );
}

// spec: BIT-OPERATORS-1
test "the integer bit operators are refused with the prelude call" {
    try expectRejected(
        // migrate-embedded: skip retired bit-operator refusal and exact replacement witness
        \\func main() -> int:
        \\    return 6 & 3
    , bit_operators.code, bit_operators.message);
    try expectRejected(
        // migrate-embedded: skip retired bit-operator refusal and exact replacement witness
        \\func main() -> int:
        \\    return 6 | 3
    , bit_operators.code, bit_operators.message);
    try expectRejected(
        // migrate-embedded: skip retired bit-operator refusal and exact replacement witness
        \\func main() -> int:
        \\    return 6 ^ 3
    , bit_operators.code, bit_operators.message);
}

// spec: BIT-OPERATORS-1
test "the repair names the operator's prelude call with both operands" {
    var buffer: [64]u8 = undefined;
    try t.expectEqualStrings("bit_and(6, 3)", try fixText(&buffer,
        // migrate-embedded: skip retired bit-operator refusal and exact replacement witness
        \\func main() -> int:
        \\    return 6 & 3
    ));
    try t.expectEqualStrings("bit_or(6, 3)", try fixText(&buffer,
        // migrate-embedded: skip retired bit-operator refusal and exact replacement witness
        \\func main() -> int:
        \\    return 6 | 3
    ));
    try t.expectEqualStrings("bit_xor(6, 3)", try fixText(&buffer,
        // migrate-embedded: skip retired bit-operator refusal and exact replacement witness
        \\func main() -> int:
        \\    return 6 ^ 3
    ));
}

// spec: BIT-OPERATORS-2
test "the set operators stay a set's spelling" {
    try accepted(
        \\func main() -> int:
        \\    mut left = {1, 2}
        \\    mut right = {2, 3}
        \\    return len(left | right) * 10 + len(left & right)
    );
}

// spec: BIT-OPERATORS-2
test "a non-integer operand keeps the set operator refusal" {
    try expectRejected(
        \\func main() -> int:
        \\    return 0 & "a"
    , "E_SET_OPERATOR", "`&` combines two sets or two integers (`bit_and(a, b)`)");
}

// spec: BIT-OPERATORS-1
test "a template body refuses the integer bit operators too" {
    try expectRejected(
        // migrate-embedded: skip retired bit-operator refusal and exact replacement witness
        \\func combine[T: integer](value: T, other: T) -> T:
        \\    return value & other
        \\
        \\
        \\func main() -> int:
        \\    return combine(6, 3)
    , bit_operators.code, bit_operators.message);
}

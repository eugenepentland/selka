//! One presence spelling for `Option[T]`: `value is None` / `value is not
//! None`, the refusal of `== None`, `!= None`, `.is_none()` and `.is_some()`,
//! and the certain repair each removed form carries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

/// Check a program that must be accepted.
fn accepted(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "option.selka", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

/// Check a program that must be rejected with `code` and exactly `message`.
fn expectRejected(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "option.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expectEqualStrings(message, compilation.diagnostics.items[0].message);
}

/// Copy the replacement text of the first diagnostic's repair into `buffer`,
/// which outlives the compilation that produced it.
fn fixText(buffer: []u8, text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "option.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const fix = compilation.diagnostics.items[0].provenance.fix orelse return "";
    try t.expect(fix.edit.text.len <= buffer.len);
    @memcpy(buffer[0..fix.edit.text.len], fix.edit.text);
    return buffer[0..fix.edit.text.len];
}

const comparison_code = @import("option_spelling.zig").comparison_code;
const method_code = @import("option_spelling.zig").method_code;
const comparison_message = @import("option_spelling.zig").comparison_message;
const method_message = @import("option_spelling.zig").method_message;

// spec: OPTION-PRESENCE-1
test "presence is the identity test, in both directions" {
    try accepted(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    if value is None:
        \\        return 0
        \\    if value is not None:
        \\        return 1
        \\    return 2
    );
}

// spec: OPTION-PRESENCE-1
test "a presence comparison is refused with its identity test" {
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value == None
    , comparison_code, comparison_message);
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value != None
    , comparison_code, comparison_message);
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return None == value
    , comparison_code, comparison_message);
}

// spec: OPTION-PRESENCE-1
test "the comparison repair keeps the operand and names the identity test" {
    var buffer: [64]u8 = undefined;
    try t.expectEqualStrings("value is None", try fixText(&buffer,
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value == None
    ));
    try t.expectEqualStrings("value is not None", try fixText(&buffer,
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return None != value
    ));
}

// spec: OPTION-PRESENCE-2
test "a presence method is refused with its identity test" {
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value.is_none()
    , method_code, method_message);
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value.is_some()
    , method_code, method_message);
    // The refusal outranks arity: the method itself is gone.
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value.is_none(1)
    , method_code, method_message);
}

// spec: OPTION-PRESENCE-2
test "the method repair replaces the call, keeping the receiver text" {
    var buffer: [64]u8 = undefined;
    try t.expectEqualStrings(" is None", try fixText(&buffer,
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value.is_none()
    ));
    try t.expectEqualStrings(" is not None", try fixText(&buffer,
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value.is_some()
    ));
}

// spec: OPTION-PRESENCE-2
test "a comparison beside a presence test has no certain repair" {
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value.is_none() == True
    , method_code, method_message);
}

// spec: OPTION-PRESENCE-1
test "a chain of comparisons still names the removed presence test" {
    try expectRejected(
        \\func half(n: int) -> int?:
        \\    return Some(n)
        \\
        \\
        \\func main() -> int:
        \\    if half(2) == None == half(3):
        \\        return 0
        \\    return 1
    , comparison_code, comparison_message);
}

// spec: OPTION-PRESENCE-1
test "the unit literal is not a None operand" {
    try expectRejected(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    if value == ():
        \\        return 0
        \\    return 1
    , "E_TYPE", "expected int?, found Unit");
}

// spec: OPTION-PRESENCE-1
test "a generic body refuses the removed comparison too" {
    try expectRejected(
        // migrate-embedded: skip original generic removed-None-comparison refusal witness
        \\func head[T: copy + storable](values: T[]) -> T?:
        \\    if len(values) == 0:
        \\        return None
        \\    return Some(values[0])
        \\
        \\
        \\func present[T: copy + storable](values: T[]) -> bool:
        \\    return head(values) != None
    , comparison_code, comparison_message);
}

//! The refusals lane FR2 made clearer (13 November 2026), each from an entry of the site project's friction log: the
//! compiler was right to refuse and the message named the wrong cause or a repair the next round took back. Each test
//! is one refused program, the code of its first diagnostic, the words that name the cause, and the certain edit where
//! the refusal carries one. The rules themselves did not change; the ownership refusals are tested in
//! `src/core/single_owner_test.zig` and the messages that need a module graph (an import, the module root) in
//! `test/fix_cli_test.zig`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");

/// Check `source`, which must be refused, and return its first diagnostic; the compilation must outlive it.
fn firstRefusal(c: *language.Compilation) !diagnostic.Diagnostic {
    try t.expectError(error.SourceError, c.check());
    try t.expect(c.diagnostics.items.len != 0);
    return c.diagnostics.items[0];
}

/// Require the first diagnostic of `source` to carry `code` and a message containing `words`.
fn expectRefusal(source: []const u8, code: []const u8, words: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "friction.selka", source);
    defer c.deinit();
    const first = try firstRefusal(&c);
    try t.expectEqualStrings(code, first.code);
    try t.expect(std.mem.indexOf(u8, first.message, words) != null);
}

/// Require the first diagnostic of `source` to carry `code` and a fix whose first edit replaces the text `replaced` with
/// `text` (a later edit may add the import the replacement needs).
fn expectFix(source: []const u8, code: []const u8, replaced: []const u8, text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "friction.selka", source);
    defer c.deinit();
    const first = try firstRefusal(&c);
    try t.expectEqualStrings(code, first.code);
    try t.expect(first.provenance.fix != null);
    const fix = first.provenance.fix.?;
    try t.expectEqualStrings(replaced, c.src.text(fix.edit.span));
    try t.expectEqualStrings(text, fix.edit.text);
}

/// Require the first diagnostic of `source` to carry `code` and no fix.
fn expectNoFix(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "friction.selka", source);
    defer c.deinit();
    const first = try firstRefusal(&c);
    try t.expectEqualStrings(code, first.code);
    try t.expect(first.provenance.fix == null);
}

const unit_step_head = "func step(ok: bool) -> Unit fails str:\n    if not ok:\n        fail \"no\"\n";
const unit_main = "\n\nfunc main() -> int:\n    return 0\n";

test "F-41 return Unit() names the bare return and deletes the value" {
    const constructed = unit_step_head ++ "    return Unit()\n" ++ unit_main;
    try expectRefusal(constructed, "E_UNKNOWN_FUNCTION", "a function that returns `Unit` ends with a bare `return`");
    try expectFix(constructed, "E_UNKNOWN_FUNCTION", " Unit()", "");
    // `return unit` and `return Unit` are the same mistake, and a function without `fails` too.
    try expectFix(unit_step_head ++ "    return unit\n" ++ unit_main, "E_UNKNOWN_FUNCTION", " unit", "");
    try expectFix("func step() -> Unit:\n    return Unit\n" ++ unit_main, "E_UNKNOWN_FUNCTION", " Unit", "");
}

test "F-41 Unit() outside a return names its value, and a declared unit keeps its own check" {
    // A value position has no bare form to write, so the message names `()` and carries no edit.
    const wrapped = "func step() -> Result[Unit, str]:\n    return Ok(Unit())\n" ++ unit_main;
    try expectRefusal(wrapped, "E_UNKNOWN_FUNCTION", "its one value is written `()`");
    try expectNoFix(wrapped, "E_UNKNOWN_FUNCTION");
    // A function named `unit` is a real name: `return unit` is its ordinary type error, not this refusal.
    const declared = "func unit(a: int, b: int, c: int) -> int:\n    return a + b + c\n\nfunc step() -> Unit:\n    return unit\n" ++ unit_main;
    var c = try language.Compilation.init(t.allocator, "friction.selka", declared);
    defer c.deinit();
    const first = try firstRefusal(&c);
    try t.expect(std.mem.indexOf(u8, first.message, "bare `return`") == null);
}

test "F-10 a binding named like a function, a local, a constant or a type says which" {
    const payload = "func reason(code: int) -> str:\n    return str(code)\n\nfunc describe(r: Result[int, str]) -> str:\n" ++
        "    match r:\n        case Ok(value):\n            return reason(value)\n        case Err(reason):\n            return reason\n" ++ unit_main;
    try expectRefusal(payload, "E_SHADOWING", "payload binding `reason` would hide the function `reason`");
    const local = "func f() -> int:\n    const a = 1\n    if a == 1:\n        const a = 2\n        return a\n    return a\n" ++ unit_main;
    try expectRefusal(local, "E_SHADOWING", "binding `a` would hide the local `a`");
    const constant = "const LIMIT: int = 3\n\nfunc f() -> int:\n    const LIMIT = 4\n    return LIMIT\n" ++ unit_main;
    try expectRefusal(constant, "E_SHADOWING", "binding `LIMIT` would hide the module constant `LIMIT`");
    const record = "record Point:\n    x: int\n\nfunc f(Point: int) -> int:\n    return Point\n" ++ unit_main;
    try expectRefusal(record, "E_SHADOWING", "parameter `Point` would hide the type `Point`");
    // Choosing a name is not a certain edit: no rename is offered. A name taken by an import is tested in
    // `test/fix_cli_test.zig`, which loads a module graph.
    try expectNoFix(payload, "E_SHADOWING");
}

test "F-2 a set's add method becomes sets.include for a lent value and sets.add for one the caller can give" {
    const set_head = "func f(mut seen: set[str], name: str):\n";
    const owned = set_head ++ "    const made = name + \"!\"\n    seen.add(made)\n" ++ unit_main;
    try expectFix(owned, "E_METHOD_REMOVED", "seen.add(made)", "sets.add(mut seen, made)");
    try expectRefusal(set_head ++ "    seen.add(name)\n" ++ unit_main, "E_METHOD_REMOVED", "write `sets.include(mut values, value)`");
    try expectFix(set_head ++ "    seen.add(name)\n" ++ unit_main, "E_METHOD_REMOVED", "seen.add(name)", "sets.include(mut seen, name)");
    try expectFix(set_head ++ "    seen.add(\"x\")\n" ++ unit_main, "E_METHOD_REMOVED", "seen.add(\"x\")", "sets.add(mut seen, \"x\")");
}

// F-38 (`str` and `repr` of a list, a set, a dictionary or an option) is tested in `src/collection_text_test.zig`.

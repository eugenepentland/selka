//! No-argument `split`, prelude `ord`/`chr`, and the call-site rejections that
//! name the callee's checked signature. Every behavioral line here carries the
//! `// spec:` tag its `SPEC.md` bullet names.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const diagnostic_output = @import("diagnostic_output.zig");

/// Run one program natively and require its exit value.
fn run(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "split.my", text);
    defer compilation.deinit();
    const result = native.runWithOptions(&compilation, .{}) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s}\n", .{ diag.code, diag.message });
        return err;
    };
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}

/// Run one program natively and require the named trap.
fn trapped(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "scalar.my", text);
    defer compilation.deinit();
    const result = try native.runWithOptions(&compilation, .{});
    try t.expect(result.trapped());
    try t.expectEqualStrings(code, result.trap.code);
}

test "split with no argument breaks on runs of whitespace and drops empty parts" {
    // spec: SPLIT-WHITESPACE-1
    try run(
        \\def main() -> int:
        \\    parts = "a  b\tc".split()
        \\    if len(parts) != 3:
        \\        return 1
        \\    if parts[0] != "a" or parts[1] != "b" or parts[2] != "c":
        \\        return 2
        \\    if len("".split()) != 0 or len("   ".split()) != 0:
        \\        return 3
        \\    if len(" a ".split()) != 1:
        \\        return 4
        \\    if len("a\nb\rc\x0bd\x0cf".split()) != 5:
        \\        return 5
        \\    if len("h\u00e9llo w\u00f6rld".split()) != 2:
        \\        return 6
        \\    return len(parts) * 14
        \\
    , 42);
}

test "split with a separator keeps its exact-separator meaning" {
    // spec: SPLIT-WHITESPACE-2
    try run(
        \\def main() -> int:
        \\    if len("a,b,c".split(",")) != 3:
        \\        return 1
        \\    if len("a,,b".split(",")) != 3:
        \\        return 2
        \\    if len("  spaced  ".split(" ")) != 5:
        \\        return 3
        \\    return 42
        \\
    , 42);
}

test "bytes split with no argument breaks on the six ASCII whitespace octets" {
    // spec: SPLIT-WHITESPACE-3
    try run(
        \\def main() -> int:
        \\    parts = b" a\tb "
        \\    if len(parts.split()) != 2:
        \\        return 1
        \\    if parts.split()[0] != b"a":
        \\        return 2
        \\    if len(b"".split()) != 0:
        \\        return 3
        \\    if len(b"x,,y".split(b",")) != 3:
        \\        return 4
        \\    return 42
        \\
    , 42);
}

test "ord and chr fold a one-scalar literal and run any one Unicode scalar" {
    // spec: PRELUDE-SCALAR-1
    try run(
        \\def main() -> int:
        \\    if ord("A") != 65 or ord("m") != 109 or ord("\u00e9") != 233:
        \\        return 1
        \\    text = "m"
        \\    if ord(text) != 109:
        \\        return 2
        \\    if chr(65) != "A" or chr(233) != "\u00e9":
        \\        return 3
        \\    wide = chr(128512)
        \\    if len(wide) != 1 or ord(wide) != 128512:
        \\        return 4
        \\    if ord(chr(1114111)) != 1114111:
        \\        return 5
        \\    return 42
        \\
    , 42);
}

test "ord and chr trap R_TEXT_SCALAR on anything but one Unicode scalar" {
    // spec: PRELUDE-SCALAR-2
    try trapped("def main() -> int:\n    return ord(\"ab\")\n", "R_TEXT_SCALAR");
    try trapped("def main() -> int:\n    return ord(\"\")\n", "R_TEXT_SCALAR");
    try trapped("def main() -> int:\n    text = \"ab\"\n    return ord(text)\n", "R_TEXT_SCALAR");
    try trapped("def main() -> int:\n    return len(chr(0 - 1))\n", "R_TEXT_SCALAR");
    try trapped("def main() -> int:\n    return len(chr(55296))\n", "R_TEXT_SCALAR");
    try trapped("def main() -> int:\n    return len(chr(1114112))\n", "R_TEXT_SCALAR");
}

test "ord of a one-scalar literal lowers to the same QBE as the raw code" {
    // spec: PRELUDE-SCALAR-3
    const folded =
        \\def letter(code: int) -> bool:
        \\    return code == ord("m")
        \\
        \\
        \\def main() -> int:
        \\    if letter(109):
        \\        return 42
        \\    return 1
        \\
    ;
    const raw =
        \\def letter(code: int) -> bool:
        \\    return code == 109
        \\
        \\
        \\def main() -> int:
        \\    if letter(109):
        \\        return 42
        \\    return 1
        \\
    ;
    var first = try language.Compilation.init(t.allocator, "fold.my", folded);
    defer first.deinit();
    var second = try language.Compilation.init(t.allocator, "fold.my", raw);
    defer second.deinit();
    const left = try first.emitQbe(t.allocator);
    defer t.allocator.free(left);
    const right = try second.emitQbe(t.allocator);
    defer t.allocator.free(right);
    try t.expectEqualStrings(left, right);
    try t.expect(std.mem.indexOf(u8, left, "call $myl_native_text_ord") == null);
}

test "requireArgument attaches the callee signature to a rejected argument" {
    // spec: DIAGNOSTIC-SITES-1
    var compilation = try language.Compilation.init(t.allocator, "sites.my", "def main() -> int:\n    return len(\"abc\".find(1))\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diag = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_TYPE", diag.code);
    const related = diag.related.?;
    try t.expectEqual(diagnostic_role(.alternative), diag.related.?.role);
    try t.expectEqualStrings("str.find(sub: str, start: int = 0, end: int = len(self)) -> int", related.message);
    const json = try diagnostic_output.render(t.allocator, diag, compilation.src, .json);
    defer t.allocator.free(json);
    try t.expect(std.mem.indexOf(u8, json, "\"version\":\"diagnostic-v1\"") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"role\":\"alternative\"") != null);
    const text = try diagnostic_output.render(t.allocator, diag, compilation.src, .text);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "alternative: str.find(sub: str, start: int = 0, end: int = len(self)) -> int") != null);
}

test "methodArityFailure prints the signature and the whitespace alternative" {
    // spec: DIAGNOSTIC-SITES-2
    var compilation = try language.Compilation.init(t.allocator, "sites.my", "def main() -> int:\n    parts = \"a b\".split(\",\", 2)\n    return len(parts)\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diag = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_ARITY", diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "`str.split(separator: str) -> list[str]` takes 1 argument, but this call passes 2") != null);
    try t.expectEqual(diagnostic_role(.alternative), diag.related.?.role);
    try t.expect(std.mem.indexOf(u8, diag.related.?.message, "runs of ASCII whitespace") != null);
}

test "an unknown method names the receiver type and its accepted repair" {
    // spec: DIAGNOSTIC-SITES-3
    var compilation = try language.Compilation.init(t.allocator, "sites.my", "def main() -> int:\n    s = \"{} items\".format(3)\n    return len(s)\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diag = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_COLLECTION_METHOD", diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "unknown method for a str receiver") != null);
    try t.expect(std.mem.indexOf(u8, diag.message, "accepted methods: ") != null);
    try t.expectEqual(diagnostic_role(.alternative), diag.related.?.role);
    try t.expect(std.mem.indexOf(u8, diag.related.?.message, "f-string") != null);
}

test "a rendered collection signature counts its own parameters" {
    // spec: DIAGNOSTIC-SITES-4
    const buffer_operations = @import("buffer_operations.zig");
    const signatures = [_]struct { kind: buffer_operations.Kind, family: @import("runtime_values.zig").ManagedKind, parameters: usize }{
        .{ .kind = .split, .family = .string, .parameters = 1 },
        .{ .kind = .split_whitespace, .family = .string, .parameters = 0 },
        .{ .kind = .join, .family = .string, .parameters = 1 },
        .{ .kind = .append, .family = .list, .parameters = 1 },
        .{ .kind = .get, .family = .dictionary, .parameters = 2 },
        .{ .kind = .buffer_append_range, .family = .bytes, .parameters = 3 },
        .{ .kind = .pop_default, .family = .dictionary, .parameters = 2 },
    };
    for (signatures) |case| {
        const names: buffer_operations.SignatureNames = .{ .receiver = "str", .family = case.family, .element = "int", .key = "str" };
        const rendered = (try buffer_operations.signatureText(t.allocator, case.kind, names)).?;
        defer t.allocator.free(rendered);
        const open = std.mem.indexOfScalar(u8, rendered, '(').?;
        const close = std.mem.indexOfScalar(u8, rendered, ')').?;
        const parameters = std.mem.count(u8, rendered[open + 1 .. close], ":");
        try t.expectEqual(case.parameters, parameters);
    }
    // An operation no source spelling names has no signature to print, and the
    // prelude's literal folding serves the rest.
    const unnamed: buffer_operations.SignatureNames = .{ .receiver = "str", .family = .string };
    try t.expectEqual(@as(?[]const u8, null), try buffer_operations.signatureText(t.allocator, .text_chr, unnamed));
}

test "a bare print carries its accepted spelling as an alternative note" {
    // spec: DIAGNOSTIC-SITES-5
    var compilation = try language.Compilation.init(t.allocator, "print.my", "def main() -> int:\n    print(\"ready\")\n    return 42\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diag = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_OUTPUT_CAPABILITY", diag.code);
    try t.expectEqualStrings(@import("io_builtins.zig").output_capability_message, diag.message);
    try t.expectEqualStrings(@import("io_builtins.zig").output_capability_message, diag.related.?.message);
    try t.expectEqual(diagnostic_role(.alternative), diag.related.?.role);
    const json = try diagnostic_output.render(t.allocator, diag, compilation.src, .json);
    defer t.allocator.free(json);
    try t.expect(std.mem.indexOf(u8, json, "\"role\":\"alternative\"") != null);
    // The message already carries the whole sentence, so the text rendering of
    // the diagnostic is unchanged by the structured note.
    const text = try diagnostic_output.render(t.allocator, diag, compilation.src, .text);
    defer t.allocator.free(text);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, text, "add `out: Stream`"));
}

/// The role the diagnostic module declares for a note, named through its own
/// type so a rename there fails here rather than drifting.
fn diagnostic_role(role: @import("diagnostic.zig").Role) @import("diagnostic.zig").Role {
    return role;
}

test "a signature note renders without a location and keeps the call's span" {
    // spec: DIAGNOSTIC-ROLE-2
    var compilation = try language.Compilation.init(t.allocator, "role.my", "def main() -> int:\n    print(\"ready\")\n    return 42\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diag = compilation.diagnostics.items[0];
    try t.expectEqual(diagnostic_role(.signature), diag.provenance.requirement.?.role);
    try t.expectEqual(diag.span, diag.provenance.requirement.?.span);
    const text = try diagnostic_output.render(t.allocator, diag, compilation.src, .text);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "  signature: ") != null);
    try t.expect(std.mem.indexOf(u8, text, "signature: role.my:") == null);
    const json = try diagnostic_output.render(t.allocator, diag, compilation.src, .json);
    defer t.allocator.free(json);
    try t.expect(std.mem.indexOf(u8, json, "\"role\":\"signature\"") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"path\":\"role.my\"") != null);
}

test "a note without a declared role keeps its evidence slot" {
    // spec: DIAGNOSTIC-ROLE-1
    var compilation = try language.Compilation.init(t.allocator, "note.my", "record P:\n    x: int\n    y: int\n\n\ndef main() -> int:\n    p = P(x=1)\n    return p.x\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diag = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_INCOMPLETE_CONSTRUCTION", diag.code);
    try t.expectEqual(diagnostic_role(.related), diag.related.?.role);
    const json = try diagnostic_output.render(t.allocator, diag, compilation.src, .json);
    defer t.allocator.free(json);
    try t.expect(std.mem.indexOf(u8, json, "\"version\":\"diagnostic-v1\"") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"role\":\"related\"") != null);
    const text = try diagnostic_output.render(t.allocator, diag, compilation.src, .text);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "  note: ") != null);
}

test "a call-site rejection carries the accepted callee as a signature note" {
    // spec: DIAGNOSTIC-SITES-6
    var printed = try language.Compilation.init(t.allocator, "signature.my", "def main() -> int:\n    print(\"ready\")\n    return 42\n");
    defer printed.deinit();
    try t.expectError(error.SourceError, printed.check());
    const print_diag = printed.diagnostics.items[0];
    try t.expectEqualStrings("E_OUTPUT_CAPABILITY", print_diag.code);
    try t.expectEqual(diagnostic_role(.signature), print_diag.provenance.requirement.?.role);
    try t.expectEqualStrings("stream.print(values..., sep: str, end: str) -> None", print_diag.provenance.requirement.?.message);
    const print_text = try diagnostic_output.render(t.allocator, print_diag, printed.src, .text);
    defer t.allocator.free(print_text);
    try t.expect(std.mem.indexOf(u8, print_text, "signature: stream.print(values..., sep: str, end: str) -> None") != null);
    var sorted = try language.Compilation.init(t.allocator, "signature.my", "def main() -> int:\n    xs = sorted([3, 1, 2], cmp=True)\n    return xs[0]\n");
    defer sorted.deinit();
    try t.expectError(error.SourceError, sorted.check());
    const sorted_diag = sorted.diagnostics.items[0];
    try t.expectEqualStrings("E_CALL_ARGUMENT", sorted_diag.code);
    try t.expectEqualStrings("sorted(values: list[T], *, key: def(T) -> K = None, reverse: bool = False) -> list[T]", sorted_diag.provenance.requirement.?.message);
    try t.expectEqual(diagnostic_role(.alternative), sorted_diag.related.?.role);
    const sorted_json = try diagnostic_output.render(t.allocator, sorted_diag, sorted.src, .json);
    defer t.allocator.free(sorted_json);
    try t.expect(std.mem.indexOf(u8, sorted_json, "\"role\":\"signature\"") != null);
    try t.expect(std.mem.indexOf(u8, sorted_json, "\"role\":\"alternative\"") != null);
}

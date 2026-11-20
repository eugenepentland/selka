//! List comprehensions build a fresh list through one checked loop.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const comprehension_path = "comprehension.selka";

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, comprehension_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-COMPREHENSION-2
test "comprehensions reject shadowing, non-Boolean filters and uniterable sources" {
    try reject(
        \\func main() -> int:
        \\    mut value = 1
        \\    _ = [for value in [1, 2] yield value]
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\func main() -> int:
        \\    _ = [for x in [1, 2] if x yield x]
        \\    return 0
    , "E_TYPE");
    try reject(
        \\func main() -> int:
        \\    _ = [for x in 3 yield x]
        \\    return 0
    , "E_COLLECTION_METHOD");
}

fn removal(source_text: []const u8, certain: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, comprehension_path, source_text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    for (compilation.diagnostics.items) |item| {
        if (!std.mem.eql(u8, item.code, "E_COMPREHENSION_REMOVED") and !std.mem.eql(u8, item.code, "E_GENERATOR_REMOVED")) continue;
        try t.expectEqual(certain, item.provenance.fix != null);
        return;
    }
    return t.expect(false);
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions infer typed accumulators and reject unsafe hoists" {
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func main() -> int:\n    return len([x + 1 for x in [1, 2]])\n", true);
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func main() -> int:\n    return sum(x for x in range(3))\n", true);
    // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
    try conditionalThenComprehension("func main() -> int:\n    return if True then 1 else len([x for x in [1, 2]])\n");
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func main() -> int:\n    mut count = 0\n    while len([x for x in [1, 2]]) > count:\n        count += 1\n    return count\n", false);
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func main() -> int:\n    if False and any(x > 0 for x in [1, 2]):\n        return 1\n    return 0\n", false);
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions do not move a gather across an earlier local read" {
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func main() -> int:\n    const x = 3\n    return x + sum(y for y in [1, 2])\n", false);
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func main() -> int:\n    return 3 + sum(y for y in [1, 2])\n", true);
}

/// Repair the owning selection first, then keep its lazy gather inside else.
fn conditionalThenComprehension(original: []const u8) !void {
    var first = try language.Compilation.init(t.allocator, comprehension_path, original);
    defer first.deinit();
    try t.expectError(error.SourceError, first.check());
    const selection = first.diagnostics.items[0];
    try t.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", selection.code);
    try t.expect(selection.provenance.fix != null);
    try t.expectEqual(@as(usize, 1), selection.provenance.fix.?.count());
    const after_selection = try appliedComprehensionRepair(original, selection.provenance.fix.?);
    defer t.allocator.free(after_selection);
    const branch_prefix = "func main() -> int:\n    if True:\n        return 1\n    else:\n";
    try t.expectEqualStrings(branch_prefix ++ "        return len([x for x in [1, 2]])\n", after_selection);

    var second = try language.Compilation.init(t.allocator, comprehension_path, after_selection);
    defer second.deinit();
    try t.expectError(error.SourceError, second.check());
    const comprehension = second.diagnostics.items[0];
    try t.expectEqualStrings("E_COMPREHENSION_REMOVED", comprehension.code);
    try t.expect(comprehension.provenance.fix != null);
    const fix = comprehension.provenance.fix.?;
    try t.expectEqual(@as(usize, 2), fix.count());
    for (0..fix.count()) |index| {
        const edit = fix.at(index);
        try t.expect(edit.span.start >= branch_prefix.len);
        try t.expect(edit.span.end <= after_selection.len);
    }
    const final_source = try appliedComprehensionRepair(after_selection, fix);
    defer t.allocator.free(final_source);
    try t.expect(std.mem.startsWith(u8, final_source, branch_prefix));
    try t.expect(std.mem.indexOf(u8, final_source, "\n        mut gather_result_") != null);
    try t.expect(std.mem.indexOf(u8, final_source, "\n        for x in [1, 2]:\n") != null);
    try t.expect(std.mem.indexOf(u8, final_source, "\n            const gather_value_") != null);
    try t.expect(std.mem.indexOf(u8, final_source, "\n        return len(gather_result_") != null);
    try t.expect(std.mem.indexOf(u8, final_source, "\n    mut gather_result_") == null);
    try t.expect(std.mem.indexOf(u8, final_source, "\n    for x in ") == null);
    var final = try language.Compilation.init(t.allocator, comprehension_path, final_source);
    defer final.deinit();
    try final.check();
    try t.expectEqual(@as(usize, 0), final.diagnostics.items.len);
}

// spec: COMPREHENSION-4
test "a comprehension passed to a method on a literal is hoisted to a loop before its statement" {
    const original = "func main() -> int:\n    const text = \", \".join([str(x) for x in [1, 2]])\n    return strings.char_count(text)\n";
    var first = try language.Compilation.init(t.allocator, comprehension_path, original);
    defer first.deinit();
    try t.expectError(error.SourceError, first.check());
    // The join on the literal is a method W13-S5 refuses, and that refusal comes first; the comprehension's is beside it.
    try t.expectEqualStrings("E_METHOD_REMOVED", first.diagnostics.items[0].code);
    const item = first.diagnostics.items[try indexOfCode(first.diagnostics.items, "E_COMPREHENSION_REMOVED")];
    try t.expect(item.provenance.fix != null);
    const repaired = try appliedComprehensionRepair(original, item.provenance.fix.?);
    defer t.allocator.free(repaired);
    try t.expect(std.mem.indexOf(u8, repaired, "\n    for x in [1, 2]:\n") != null);
    try t.expect(std.mem.indexOf(u8, repaired, "\n    const text = \", \".join(gather_result_") != null);
    var final = try language.Compilation.init(t.allocator, comprehension_path, repaired);
    defer final.deinit();
    // The join on the literal is a method W13 removed: its refusal, which the next round of `selka fix` rewrites, is
    // the one diagnostic left.
    try t.expectError(error.SourceError, final.check());
    try t.expect(final.diagnostics.items.len != 0);
    try t.expect(onlyMethodForms(final.diagnostics.items));
}

// spec-case: COMPREHENSION-4
test "a comprehension passed to a method on a variable or after an unstable operand stays unrepaired" {
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func main() -> int:\n    const sep = \", \"\n    const text = sep.join([str(x) for x in [1, 2]])\n    return strings.char_count(text)\n", false);
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func pad(prefix: str, rest: str[]) -> int:\n    return strings.char_count(prefix) + len(rest)\n\n\nfunc main() -> int:\n    return pad(\"ab\", [str(x) for x in [1, 2]])\n", true);
    // migrate-embedded: skip original comprehension hoist certainty witness
    try removal("func pad(prefix: int, rest: str[]) -> int:\n    return prefix + len(rest)\n\n\nfunc main() -> int:\n    const n = 3\n    return pad(n, [str(x) for x in [1, 2]])\n", false);
}

/// Apply one atomic diagnostic repair to an owned temporary buffer.
fn appliedComprehensionRepair(bytes: []const u8, fix: diagnostic.Fix) ![]u8 {
    const edits = try t.allocator.alloc(diagnostic.Edit, fix.count());
    defer t.allocator.free(edits);
    for (edits, 0..) |*edit, index| edit.* = fix.at(index);
    std.mem.sort(diagnostic.Edit, edits, {}, struct {
        fn later(_: void, a: diagnostic.Edit, b: diagnostic.Edit) bool {
            return a.span.start > b.span.start;
        }
    }.later);
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, bytes);
    for (edits) |edit| try text.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
    return text.toOwnedSlice(t.allocator);
}

/// The index of the first diagnostic in `items` that carries `code`.
fn indexOfCode(items: []const @import("diagnostic.zig").Diagnostic, code: []const u8) !usize {
    for (items, 0..) |item, index| if (std.mem.eql(u8, item.code, code)) return index;
    return error.TestUnexpectedResult;
}

/// Whether every diagnostic in `items` is W13's refusal of a method, `E_METHOD_REMOVED`.
fn onlyMethodForms(items: []const @import("diagnostic.zig").Diagnostic) bool {
    for (items) |item| if (!std.mem.eql(u8, item.code, "E_METHOD_REMOVED")) return false;
    return true;
}

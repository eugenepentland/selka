//! Wave-one declarations and conservative source migration primitives.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const source = @import("source.zig");
const support = @import("migration_support.zig");

fn accepted(bytes: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "declarations.selka", bytes);
    defer compilation.deinit();
    try compilation.checkLibrary();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}
fn rejected(bytes: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "declarations.selka", bytes);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
fn purity(bytes: []const u8, expected: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "purity.selka", bytes);
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const body = syntax.statements.items[@backingInt(syntax.functions[0].body)].data.block;
    const expression = syntax.statements.items[@backingInt(body[0])].data.ret;
    try t.expectEqual(expected, support.isPureOperand(syntax, expression));
    try t.expect(!support.evaluationOrderCertain(syntax, &.{expression}));
}
// spec: MIGRATION-SUPPORT-1
test "wave1 migration names avoid identifiers parameters comments and reserved names" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "names.selka", "func f(result: int) -> int:\n    # result_1 is reserved\n    const result_2 = result\n    return result_2\n");
    try t.expectEqualStrings("result_3", try support.freshName(a, src, "result"));
    try t.expectEqualStrings("result_4", try support.freshNameReserved(a, src, "result", &.{"result_3"}));
    try t.expectEqualStrings("res", try support.freshName(a, src, "res"));
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 migration insertion preserves nested indentation and leading comments" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = "func f() -> int:\n    if True:\n        # keep comment\n        return 1\n";
    const src = try source.Source.init(a, "nested.selka", bytes);
    const start = std.mem.indexOf(u8, bytes, "return").?;
    const edit = (try support.insertBeforeStatement(a, src, .{ .start = start, .end = start + 8 }, "mut value: int\nif True:\n    value = 1\n")).?;
    try t.expectEqualStrings("        ", support.indentation(src, start));
    try t.expectEqualStrings("        mut value: int\n        if True:\n            value = 1\n", edit.text);
    try t.expectEqual(start - 8, edit.span.start);
    try t.expectEqual(edit.span.start, edit.span.end);
    try t.expectEqual(@as(?@import("diagnostic.zig").Edit, null), try support.insertBeforeStatement(a, src, .{ .start = start + 7, .end = start + 8 }, "value = 1"));
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 migration purity withholds effects traps allocations and branching" {
    try purity("func f(x: int) -> int:\n    return x\n", true);
    try purity("func f(x: int) -> int:\n    return x + 1\n", false);
    try purity("func f(x: int[]) -> int:\n    return x[0]\n", false);
    try purity("func f() -> int:\n    return g()\n", false);
}
// spec: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 declarations assign before read on all continuing paths" {
    try accepted("func choose() -> int:\n    const result: int  # assigned later\n    result = 42\n    return result\n");
    try accepted("func choose(flag: bool) -> int:\n    const result: int\n    if flag:\n        result = 1\n    else:\n        result = 2\n    return result\n");
    try accepted("func choose(flag: bool) -> int:\n    const result: int\n    if flag:\n        return 1\n    else:\n        result = 2\n    return result\n");
    try rejected("func choose(flag: bool) -> int:\n    mut result: int\n    if flag:\n        result = 1\n    return result\n", "E_UNBOUND");
    try rejected("func choose() -> int:\n    mut result: int\n    return result\n", "E_UNBOUND");
    try rejected("func choose() -> int:\n    const result\n    return 1\n", "E_BINDING_INITIALIZER");
    try rejected("func choose() -> int:\n    mut result\n    return 1\n", "E_BINDING_INITIALIZER");
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 declarations loops cannot establish assignment after zero iterations" {
    try rejected("func choose(flag: bool) -> int:\n    mut result: int\n    while flag:\n        result = 1\n    return result\n", "E_UNBOUND");
    try rejected("func choose() -> int:\n    mut result: int\n    for i in range(0, 3):\n        result = i\n    return result\n", "E_UNBOUND");
    try rejected("func choose() -> int:\n    mut result: int\n    result += 1\n    return result\n", "E_UNBOUND");
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 declarations match assignments intersect continuing arms" {
    try accepted(
        \\enum Flag:
        \\    yes
        \\    no
        \\
        \\func choose(flag: Flag) -> int:
        \\    const result: int
        \\    match flag:
        \\        case yes:
        \\            result = 1
        \\        case no:
        \\            result = 2
        \\    return result
    );
    try rejected(
        \\enum Flag:
        \\    yes
        \\    no
        \\
        \\func choose(flag: Flag) -> int:
        \\    mut result: int
        \\    match flag:
        \\        case yes:
        \\            result = 1
        \\        case no:
        \\            pass
        \\    return result
    , "E_UNBOUND");
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 generic declarations preserve initialization across branches and loops" {
    try accepted("func choose[T: copy](flag: bool, value: T) -> T:\n    const result: T\n    if flag:\n        result = value\n    else:\n        return value\n    return result\n");
    try rejected("func choose[T: copy](flag: bool, value: T) -> T:\n    mut result: T\n    if flag:\n        result = value\n    return result\n", "E_UNBOUND");
    try rejected("func choose[T: copy](value: T) -> T:\n    mut result: T\n    for i in range(0, 3):\n        result = value\n    return result\n", "E_UNBOUND");
    try rejected("func choose[T: copy](value: T) -> int:\n    mut result: int[]\n    result.append(1)\n    return 1\n", "E_UNBOUND");
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 migration insertion refuses ranges crossing merged source origins" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const left = try source.Source.init(a, "left.selka", "    return 1\n");
    const right = try source.Source.init(a, "right.selka", "    return 2\n");
    const mapped = try source.Source.initMapped(a, &.{ left, right });
    try t.expectEqual(@as(?@import("diagnostic.zig").Edit, null), try support.insertBeforeStatement(a, mapped, .{ .start = 4, .end = mapped.bytes.len }, "mut result: int"));
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 declaration syntax clone and persisted cache preserve missing initializer" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var writer = language.frontend_cache.Cache.init(t.allocator, t.io, root, "wave1-declarations");
    defer writer.deinit();
    const bytes = "func f() -> int:\n    const result: int\n    result = 1\n    return result\n";
    var original = try language.Compilation.init(t.allocator, "declarations.selka", bytes);
    defer original.deinit();
    try original.parseCached(&writer);
    const cloned = try @import("ast_copy.zig").clone(arena.allocator(), original.syntax.?);
    const cloned_body = cloned.statements.items[@backingInt(cloned.functions[0].body)].data.block;
    try t.expect(!cloned.statements.items[@backingInt(cloned_body[0])].data.binding.initialized);
    var reader = language.frontend_cache.Cache.init(t.allocator, t.io, root, "wave1-declarations");
    defer reader.deinit();
    var restored = try language.Compilation.init(t.allocator, "declarations.selka", bytes);
    defer restored.deinit();
    try restored.parseCached(&reader);
    try t.expectEqual(@as(usize, 1), reader.statistics.syntax.hits);
    const body = restored.syntax.?.statements.items[@backingInt(restored.syntax.?.functions[0].body)].data.block;
    try t.expect(!restored.syntax.?.statements.items[@backingInt(body[0])].data.binding.initialized);
    try restored.checkLibrary();
    try t.expectEqual(@as(usize, 0), restored.diagnostics.items.len);
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 declarations propagation does not initialize a bypassed binding" {
    try accepted(
        \\enum Error:
        \\    failed
        \\
        \\func input() -> int fails Error:
        \\    return 1
        \\
        \\func choose(flag: bool) -> int fails Error:
        \\    const result: int
        \\    if flag:
        \\        result = try input()
        \\    else:
        \\        return 2
        \\    return result
    );
    try rejected(
        \\enum Error:
        \\    failed
        \\
        \\func input() -> int fails Error:
        \\    return 1
        \\
        \\func choose(flag: bool) -> int fails Error:
        \\    mut result: int
        \\    if flag:
        \\        result = try input()
        \\    return result
    , "E_UNBOUND");
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 generic declaration reads reject field index and augmented assignment" {
    try rejected("func choose[T: copy](value: T) -> int:\n    mut result: int[]\n    return result[0]\n", "E_UNBOUND");
    try rejected("record Pair:\n    value: int\n\nfunc choose[T: copy](value: T) -> int:\n    mut result: Pair\n    return result.value\n", "E_UNBOUND");
    try rejected("func choose[T: copy](value: T) -> int:\n    mut result: int\n    result += 1\n    return result\n", "E_UNBOUND");
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 migration CRLF insertion and independent diagnostic names preserve source" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = "func f() -> int:\r\n    # comment\r\n    return 1\r\n";
    const src = try source.Source.init(a, "crlf.selka", bytes);
    const start = std.mem.indexOf(u8, bytes, "return").?;
    const edit = (try support.insertBeforeStatement(a, src, .{ .start = start, .end = start + 8 }, "mut value: int\nvalue = 1")).?;
    try t.expectEqualStrings("    mut value: int\r\n    value = 1\r\n", edit.text);
    try t.expectEqualStrings("result_10", try support.freshNameAt(a, src, "result", 10));
    try t.expectEqualStrings("result_20", try support.freshNameAt(a, src, "result", 20));
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 migration hoist chooses the nested return instead of its parent branch" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var compilation = try language.Compilation.init(t.allocator, "nested.selka", "func f() -> int:\n    if True:\n        # keep\n        return 1\n    return 0\n");
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const start = std.mem.indexOf(u8, compilation.src.bytes, "return 1").?;
    const expression: source.Span = .{ .start = start + 7, .end = start + 8 };
    try t.expectEqual(start, support.enclosingStatement(syntax, expression).?.start);
    const edit = (try support.hoistBeforeStatement(arena.allocator(), compilation.src, syntax, expression, "mut value: int\nvalue = 1")).?;
    try t.expectEqualStrings("        mut value: int\n        value = 1\n", edit.text);
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 migration hoist cannot delay a pure read across a mutating expression" {
    var compilation = try language.Compilation.init(t.allocator, "order.selka", "func f(x: int) -> int:\n    return pair(x, change(mut x))\n");
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const body = syntax.statements.items[@backingInt(syntax.functions[0].body)].data.block;
    const expression = syntax.statements.items[@backingInt(body[0])].data.ret;
    const call = syntax.nodes.items[@backingInt(expression)].data.call;
    try t.expect(support.isPureOperand(syntax, call.arguments[0]));
    try t.expect(!support.evaluationOrderCertain(syntax, call.arguments[0..1]));
    try t.expect(support.evaluationOrderCertain(syntax, &.{}));
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 omitted declaration initializer works during scalar constant evaluation" {
    try accepted(
        \\const ANSWER: int = choose(True)
        \\
        \\func choose(flag: bool) -> int:
        \\    const result: int
        \\    if flag:
        \\        result = 42
        \\    else:
        \\        result = 0
        \\    return result
        \\
        \\func main() -> int:
        \\    return ANSWER
    );
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 generic match merges initialization across continuing arms" {
    try accepted(
        \\enum Flag:
        \\    yes
        \\    no
        \\
        \\func choose[T: copy](flag: Flag, value: T) -> T:
        \\    const result: T
        \\    match flag:
        \\        case yes:
        \\            result = value
        \\        case no:
        \\            return value
        \\    return result
    );
    try rejected(
        \\enum Flag:
        \\    yes
        \\    no
        \\
        \\func choose[T: copy](flag: Flag, value: T) -> T:
        \\    mut result: T
        \\    match flag:
        \\        case yes:
        \\            result = value
        \\        case no:
        \\            pass
        \\    return result
    , "E_UNBOUND");
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 scalar constant evaluation rejects an uninitialized declaration read" {
    try rejected("const ANSWER: int = choose()\n\nfunc choose() -> int:\n    mut result: int\n    return result\n\nfunc main() -> int:\n    return ANSWER\n", "E_UNBOUND");
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 checked purity accepts local reads and refuses constant getter calls" {
    const typed = @import("typed.zig");
    const span: source.Span = .{ .start = 0, .end = 0 };
    const nodes = [_]typed.Node{
        .{ .ty = .i64, .span = span, .data = .{ .local = @fromBackingInt(0) } },
        .{ .ty = .i64, .span = span, .data = .{ .call = .{ .function = @fromBackingInt(0), .arguments = &.{} } } },
        .{ .ty = .i64, .span = span, .data = .{ .field = .{ .base = @fromBackingInt(0), .index = 0 } } },
        .{ .ty = .i64, .span = span, .data = .{ .field = .{ .base = @fromBackingInt(1), .index = 0 } } },
    };
    try t.expect(support.isPureTypedOperand(&nodes, @fromBackingInt(0)));
    try t.expect(!support.isPureTypedOperand(&nodes, @fromBackingInt(1)));
    try t.expect(support.isPureTypedOperand(&nodes, @fromBackingInt(2)));
    try t.expect(!support.isPureTypedOperand(&nodes, @fromBackingInt(3)));
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 generic environment receiver cannot read an omitted initializer" {
    try rejected("func choose[T: copy](value: T) -> int:\n    mut env: Environment\n    const restricted = env.only(\"PATH\")\n    return 1\n", "E_UNBOUND");
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 uninitialized result obligations agree in concrete and generic branches" {
    try rejected(
        \\func choose(flag: bool) -> int:
        \\    mut pending: Result[int, int]
        \\    if flag:
        \\        pending = Ok(1)
        \\    return 0
    , "E_RESULT_PATH");
    try rejected(
        \\func choose(flag: bool) -> int:
        \\    mut pending: Result[int, int]
        \\    while flag:
        \\        pending = Ok(1)
        \\    return 0
    , "E_RESULT_LOOP");
    try accepted(
        \\func choose(flag: bool) -> int:
        \\    const pending: Result[int, int]
        \\    if flag:
        \\        pending = Ok(1)
        \\        _ = pending
        \\    return 0
    );
    try rejected(
        \\func choose[T: copy](flag: bool) -> int:
        \\    mut pending: Result[int, int]
        \\    if flag:
        \\        pending = Ok(1)
        \\    return 0
    , "E_RESULT_PATH");
    try rejected(
        \\func choose[T: copy](flag: bool) -> int:
        \\    mut pending: Result[int, int]
        \\    while flag:
        \\        pending = Ok(1)
        \\    return 0
    , "E_RESULT_LOOP");
    try accepted(
        \\func choose[T: copy](flag: bool) -> int:
        \\    const pending: Result[int, int]
        \\    if flag:
        \\        pending = Ok(1)
        \\        _ = pending
        \\    return 0
    );
}
// spec-case: MIGRATION-SUPPORT-1
test "wave1 origin-local names ignore combined prefixes and preserve own-module collisions" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const module = try source.Source.init(a, "shared.selka", "result_10 = 0\n");
    const prefix_one = try source.Source.init(a, "first.selka", "result_10_1 = 0\n");
    const prefix_two = try source.Source.init(a, "second.selka", "result_10_1 = 0\nresult_10_2 = 0\n# a longer root\n");
    const first = try source.Source.initMapped(a, &.{ prefix_one, module });
    const second = try source.Source.initMapped(a, &.{ prefix_two, module });
    const first_point = try first.mappedSpan(1, .{ .start = 10, .end = 10 });
    const second_point = try second.mappedSpan(1, .{ .start = 10, .end = 10 });
    try t.expectEqualStrings("result_10_1", try support.freshOriginNameAt(a, module, "result", 10));
    try t.expectEqualStrings("result_10_1", try support.freshOriginNameAt(a, first, "result", first_point.start));
    try t.expectEqualStrings("result_10_1", try support.freshOriginNameAt(a, second, "result", second_point.start));
    try t.expectError(error.InvalidSourceSpan, support.freshOriginNameAt(a, first, "result", first.bytes.len + 1));
}

// spec: SOURCE-TYPES-1
test "wave1 source-local type names retain external qualified tokens" {
    const rendered = "dict[shared.Box[shared.Kind], other.shared.Box]";
    const local = try support.localTypeText(t.allocator, rendered, "shared.");
    defer t.allocator.free(local);
    try t.expectEqualStrings("dict[Box[Kind], other.shared.Box]", local);
    const untouched = try support.localTypeText(t.allocator, "unshared.Box", "shared.");
    defer t.allocator.free(untouched);
    try t.expectEqualStrings("unshared.Box", untouched);
    try t.expectEqualStrings(rendered, try support.localTypeText(t.allocator, rendered, ""));
}

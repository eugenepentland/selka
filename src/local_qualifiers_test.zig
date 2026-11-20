//! A local named like the root of an imported module path reads as the local (`local_qualifiers.zig`).
const std = @import("std");
const t = std.testing;
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");

/// Parse `text` as a module, the way a project load does, into the arena `a`.
fn parseModule(a: std.mem.Allocator, text: []const u8) !ast.Program {
    var sink: diagnostic.Sink = .{ .allocator = a };
    const src = try source.Source.init(a, "m.selka", text);
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var parse: parser.Parser = .{ .src = src, .storage = a, .tokens = tokens, .sink = &sink };
    return parse.parseModule();
}

/// The spelling of the first node of the program that matches `tag` and whose source text is `text`, or null.
fn spelled(program: ast.Program, src: source.Source, comptime tag: std.meta.Tag(@FieldType(ast.Node, "data")), text: []const u8) ?ast.Node {
    for (program.nodes.items) |node| {
        if (std.meta.activeTag(node.data) != tag) continue;
        if (std.mem.eql(u8, src.text(node.span), text)) return node;
    }
    return null;
}

const header =
    \\import eval.deprecations as eval_deprecations
    \\import state
    \\
;

test "local qualifier: a parameter named like a path root makes the qualified name its field chain" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = header ++
        \\func count(eval: state.Holder) -> int:
        \\    return len(eval.deprecations.items)
        \\
    ;
    const program = try parseModule(a, text);
    const src = try source.Source.init(a, "m.selka", text);
    const chain = spelled(program, src, .field, "eval.deprecations.items").?;
    try t.expectEqualStrings("items", src.text(chain.data.field.name));
    const inner = program.nodes.items[@backingInt(chain.data.field.base)];
    try t.expectEqualStrings("deprecations", src.text(inner.data.field.name));
    try t.expectEqualStrings("eval", src.text(program.nodes.items[@backingInt(inner.data.field.base)].data.name));
    try t.expect(spelled(program, src, .name, "eval.deprecations.items") == null);
}

test "local qualifier: a local declared, looped over or matched reads as itself for the rest of its scope and no further" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = header ++
        \\func scopes(rows: state.Holder[], maybe: state.Holder?) -> int:
        \\    mut total = 0
        \\    if True:
        \\        const eval = rows[0]
        \\        total += len(eval.deprecations.items)
        \\    total += eval.deprecations.LIMIT
        \\    for eval in rows:
        \\        total += len(eval.deprecations.items)
        \\    match maybe:
        \\        case Some(eval):
        \\            total += len(eval.deprecations.items)
        \\        case None:
        \\            total += eval.deprecations.COUNT
        \\    const eval = rows[0]
        \\    return total + eval.deprecations.total
        \\
    ;
    const program = try parseModule(a, text);
    const src = try source.Source.init(a, "m.selka", text);
    var chains: usize = 0;
    var paths: usize = 0;
    for (program.nodes.items) |node| {
        if (std.meta.activeTag(node.data) == .field and std.mem.eql(u8, src.text(node.data.field.name), "items")) chains += 1;
        if (std.meta.activeTag(node.data) == .name and std.mem.startsWith(u8, src.text(node.data.name), "eval.deprecations.")) paths += 1;
    }
    // Three reads of `.items` sit in a scope of `eval`; the two `LIMIT` and `COUNT` uses follow the scope's end.
    try t.expectEqual(@as(usize, 3), chains);
    try t.expectEqual(@as(usize, 2), paths);
    try t.expect(spelled(program, src, .name, "eval.deprecations.LIMIT") != null);
    try t.expect(spelled(program, src, .name, "eval.deprecations.COUNT") != null);
    // The declaration at the end of the function binds for its last statement.
    try t.expect(spelled(program, src, .field, "eval.deprecations.total") != null);
}

test "local qualifier: a call on a field of the local is a method call on the chain, not a call of the module's function" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = header ++
        \\func notes(eval: state.Holder) -> int:
        \\    eval.deprecations.note(1)
        \\    eval.deprecations.items.append(2)
        \\    eval.name.upper()
        \\    return eval_deprecations.total(eval.deprecations)
        \\
    ;
    const program = try parseModule(a, text);
    const src = try source.Source.init(a, "m.selka", text);
    const first = spelled(program, src, .method_call, "eval.deprecations.note(1)").?;
    try t.expectEqualStrings("note", src.text(first.data.method_call.name));
    try t.expectEqualStrings("deprecations", src.text(program.nodes.items[@backingInt(first.data.method_call.base)].data.field.name));
    const second = spelled(program, src, .method_call, "eval.deprecations.items.append(2)").?;
    try t.expectEqualStrings("append", src.text(second.data.method_call.name));
    const plain = spelled(program, src, .call, "eval.name.upper()");
    try t.expect(plain == null);
    // The module function called through its alias is untouched.
    const module_call = spelled(program, src, .call, "eval_deprecations.total(eval.deprecations)").?;
    try t.expectEqualStrings("eval_deprecations.total", src.text(module_call.data.call.name));
}

test "local qualifier: a qualified name with no local of that name in force stays the module path" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = header ++
        \\func uses_module(rows: state.Holder[]) -> int:
        \\    const limit = eval.deprecations.LIMIT
        \\    for row in rows:
        \\        _ = row
        \\    return limit + eval.deprecations.other
        \\
    ;
    const program = try parseModule(a, text);
    const src = try source.Source.init(a, "m.selka", text);
    try t.expect(spelled(program, src, .name, "eval.deprecations.LIMIT") != null);
    try t.expect(spelled(program, src, .name, "eval.deprecations.other") != null);
    try t.expect(spelled(program, src, .field, "eval.deprecations.other") == null);
}

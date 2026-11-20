//! The resolver behind `selka rename`: every token spelled a name gets the declaration the checker resolves it to.
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const pc = @import("project_compile.zig");
const uses = @import("rename_uses.zig");

/// Two in-memory modules: `main.selka` and `values.selka`.
const Files = struct {
    main: []const u8,
    values: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        const bytes = if (std.mem.eql(u8, path, "main.selka")) self.main else if (std.mem.eql(u8, path, "values.selka")) self.values else return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }
};

const values_module =
    \\public enum Value:
    \\    null
    \\    integer(value: i64)
    \\    text(value: str)
    \\
    \\public record Box:
    \\    value: i64
    \\
    \\public func size(item: Value) -> int:
    \\    match item:
    \\        case null:
    \\            return 0
    \\        case integer(value=number):
    \\            return int(number)
    \\        case text(value):
    \\            return len(value)
    \\
;

const main_module =
    \\import values as v
    \\
    \\func main() -> int:
    \\    const value = v.Box(value=2)
    \\    return v.size(v.Value.integer(value=3)) + int(value.value)
    \\
;

/// What the token starting at `needle`'s `occurrence`-th appearance in module `which` means, as a declaration's offset in
/// its own file (or a tag for the other meanings).
const Answer = union(enum) { declaration: struct { module: usize, start: usize }, shorthand, other, ambiguous, unresolved };

fn meaningAt(compilation: *pc.Compilation, table: *const uses.Table, which: usize, needle: []const u8, occurrence: usize) !Answer {
    const bytes = compilation.index.project.modules.items[which].src.bytes;
    var from: usize = 0;
    var seen: usize = 0;
    const local = while (std.mem.indexOfPos(u8, bytes, from, needle)) |at| : (from = at + 1) {
        if (seen == occurrence) break at;
        seen += 1;
    } else return error.TestUnexpectedResult;
    const merged = try compilation.src.mappedSpan(which, .{ .start = local, .end = local + needle.len });
    const found = table.at(merged.start) orelse return .unresolved;
    return switch (found.meaning) {
        .declaration => |span| blk: {
            const original = try compilation.src.originalSpan(span);
            break :blk .{ .declaration = .{ .module = original.input, .start = original.span.start } };
        },
        .shorthand => .shorthand,
        .other => .other,
        .ambiguous => .ambiguous,
    };
}

fn declaredAt(compilation: *pc.Compilation, which: usize, needle: []const u8, occurrence: usize) !Answer {
    const bytes = compilation.index.project.modules.items[which].src.bytes;
    var from: usize = 0;
    var seen: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, from, needle)) |at| : (from = at + 1) {
        if (seen == occurrence) return .{ .declaration = .{ .module = which, .start = at } };
        seen += 1;
    }
    return error.TestUnexpectedResult;
}

// spec: RENAME-USES-1
test "RENAME-USES-1: one spelling in several roles resolves to its own declaration in each, through an alias, a pattern label and a shorthand" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var files: Files = .{ .main = main_module, .values = values_module };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const table = try uses.resolve(arena.allocator(), &compilation, "value");
    try t.expect(table.checked);
    const main: usize = 0;
    const values: usize = for (project.modules.items, 0..) |module, position| {
        if (std.mem.eql(u8, module.name, "values")) break position;
    } else return error.TestUnexpectedResult;
    const integer_value = try declaredAt(&compilation, values, "value: i64", 0);
    const box_value = try declaredAt(&compilation, values, "value: i64", 1);
    // The constructor's label in `main` is the case's field; the record's label and read are the record's field.
    try t.expectEqualDeep(integer_value, try meaningAt(&compilation, &table, main, "value=3", 0));
    try t.expectEqualDeep(box_value, try meaningAt(&compilation, &table, main, "value=2", 0));
    try t.expectEqualDeep(box_value, try meaningAt(&compilation, &table, main, "value)\n", 0));
    // `const value` is a local; its read before `.value` is that local.
    const local = try declaredAt(&compilation, main, "value = v.Box", 0);
    try t.expectEqualDeep(local, try meaningAt(&compilation, &table, main, "value.value", 0));
    // In the library, the pattern label names `integer`'s field, and `case text(value)` is a shorthand.
    try t.expectEqualDeep(integer_value, try meaningAt(&compilation, &table, values, "value=number", 0));
    try t.expectEqual(Answer.shorthand, try meaningAt(&compilation, &table, values, "value):", 0));
    // The shorthand's local is read in its arm.
    const shorthand_local = try declaredAt(&compilation, values, "value):", 0);
    try t.expectEqualDeep(shorthand_local, try meaningAt(&compilation, &table, values, "value)\n", 0));
}

const bind_or_else =
    \\func half(n: int) -> int fails str:
    \\    if n % 2 == 1:
    \\        fail "odd"
    \\    return n // 2
    \\
    \\func main() -> int:
    \\    const parsed = half(4) else Err(problem):
    \\        return len(problem)
    \\    return parsed
    \\
;

// spec: RENAME-USES-2
test "RENAME-USES-2: the local a bind-or-else declares, and its failure arm's binding, are plain locals read where they are used" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var files: Files = .{ .main = bind_or_else, .values = "" };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const parsed = try uses.resolve(arena.allocator(), &compilation, "parsed");
    const declared = try declaredAt(&compilation, 0, "parsed =", 0);
    try t.expectEqualDeep(declared, try meaningAt(&compilation, &parsed, 0, "parsed\n", 0));
    const problem = try uses.resolve(arena.allocator(), &compilation, "problem");
    const binding = try declaredAt(&compilation, 0, "problem):", 0);
    try t.expectEqualDeep(binding, try meaningAt(&compilation, &problem, 0, "problem)\n", 0));
}

const unchecked =
    \\record Counter:
    \\    count: int
    \\
    \\func bump() -> int:
    \\    const c = Counter(count=1)
    \\    return c.count + 1
    \\
    \\func broken() -> int:
    \\    return "not a number"
    \\
    \\func main() -> int:
    \\    return bump()
    \\
;

// spec: RENAME-USES-3
test "RENAME-USES-3: without a checked tree a field read from an undeclared local is left unresolved, and a constructor's label is still resolved" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var files: Files = .{ .main = unchecked, .values = "" };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    const table = try uses.resolve(arena.allocator(), &compilation, "count");
    try t.expect(!table.checked);
    const field = try declaredAt(&compilation, 0, "count: int", 0);
    try t.expectEqualDeep(field, try meaningAt(&compilation, &table, 0, "count=1", 0));
    try t.expectEqual(Answer.unresolved, try meaningAt(&compilation, &table, 0, "count + 1", 0));
}

const chained_store =
    \\record Cluster:
    \\    unbounded: str? = None
    \\
    \\record Walker:
    \\    c: Cluster
    \\
    \\func note(mut self: Walker, message: str):
    \\    if self.c.unbounded is None:
    \\        self.c.unbounded = Some(copy(message))
    \\
    \\func main() -> int:
    \\    mut w = Walker(c=Cluster())
    \\    note(mut w, "x")
    \\    return 0
    \\
;

// spec: RENAME-USES-4
test "RENAME-USES-4: a field written through a chain of fields is the field the declared types along the chain name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var files: Files = .{ .main = chained_store, .values = "" };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const table = try uses.resolve(arena.allocator(), &compilation, "unbounded");
    const field = try declaredAt(&compilation, 0, "unbounded: str?", 0);
    try t.expectEqualDeep(field, try meaningAt(&compilation, &table, 0, "unbounded is None", 0));
    try t.expectEqualDeep(field, try meaningAt(&compilation, &table, 0, "unbounded = Some", 0));
}

const hides_alias =
    \\import values as v
    \\
    \\func count(v: v.Box) -> int:
    \\    return int(v.value)
    \\
    \\func main() -> int:
    \\    return count(v.Box(value=2))
    \\
;

// spec: RENAME-USES-5
test "RENAME-USES-5: where a parameter takes an import alias's name (E_SHADOWING), its type stays the module's, its reads are the parameter's, and the import's own token names nothing" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var files: Files = .{ .main = hides_alias, .values = values_module };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    compilation.check() catch {};
    const table = try uses.resolve(arena.allocator(), &compilation, "v");
    const main: usize = 0;
    const parameter = try declaredAt(&compilation, main, "v: v.Box", 0);
    try t.expectEqualDeep(parameter, try meaningAt(&compilation, &table, main, "v: v.Box", 0));
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &table, main, "v.Box)", 0));
    try t.expectEqualDeep(parameter, try meaningAt(&compilation, &table, main, "v.value", 0));
    // The alias after `as` names the module too.
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &table, main, "v\n", 0));
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &table, main, "v.Box(value", 0));
}

const triple_hole_module =
    \\func shout(text: str) -> str:
    \\    return text + "!"
    \\
    \\func main(out: Stream) -> int:
    \\    const name = "ada"
    \\    const page = f"""<ul>
    \\  <li>{shout(name)}</li>
    \\  <li>{{name}} {name}</li>
    \\</ul>"""
    \\    print(out, page)
    \\    return 0
    \\
;

test "RENAME-USES-F19: a name in a hole on a later line of a triple-quoted format string resolves to its declaration" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var files: Files = .{ .main = triple_hole_module, .values = "" };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const local_table = try uses.resolve(arena.allocator(), &compilation, "name");
    try t.expect(local_table.checked);
    const local = try declaredAt(&compilation, 0, "name = \"ada\"", 0);
    // `{name}` inside the hole on the literal's third line is the local; the text `{{name}}` before it is not a use.
    try t.expectEqualDeep(local, try meaningAt(&compilation, &local_table, 0, "name)}", 0));
    try t.expectEqualDeep(local, try meaningAt(&compilation, &local_table, 0, "name}</li>", 0));
    const function_table = try uses.resolve(arena.allocator(), &compilation, "shout");
    const function = try declaredAt(&compilation, 0, "shout(text", 0);
    try t.expectEqualDeep(function, try meaningAt(&compilation, &function_table, 0, "shout(name)", 0));
}

const marker_names =
    \\func labelled(named named: int, named total: int) -> int:
    \\    return named * 10 + total
    \\
    \\func add(mut: int, mut total: int) -> int:
    \\    total += mut
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    mut sum = 1
    \\    print(out, str(add(2, mut sum) + labelled(named=1, total=2)))
    \\    return 0
    \\
;

// spec: RENAME-USES-6
test "RENAME-USES-6 (FR30): a marker word before a name is no use of a parameter called the same, and the parameter's own reads are" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var files: Files = .{ .main = marker_names, .values = "" };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const named = try uses.resolve(arena.allocator(), &compilation, "named");
    const parameter = try declaredAt(&compilation, 0, "named: int", 0);
    // `named named: int, named total: int`: each leading `named` is the modifier, the second is the parameter's name.
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &named, 0, "named named", 0));
    try t.expectEqualDeep(parameter, try meaningAt(&compilation, &named, 0, "named: int", 0));
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &named, 0, "named total", 0));
    try t.expectEqualDeep(parameter, try meaningAt(&compilation, &named, 0, "named * 10", 0));
    try t.expectEqualDeep(parameter, try meaningAt(&compilation, &named, 0, "named=1", 0));
    // `mut` is a parameter's name, the modifier of `mut total` and `mut sum` (a binding and a call argument).
    const mut = try uses.resolve(arena.allocator(), &compilation, "mut");
    const mut_parameter = try declaredAt(&compilation, 0, "mut: int", 0);
    try t.expectEqualDeep(mut_parameter, try meaningAt(&compilation, &mut, 0, "mut: int", 0));
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &mut, 0, "mut total", 0));
    try t.expectEqualDeep(mut_parameter, try meaningAt(&compilation, &mut, 0, "mut\n", 0));
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &mut, 0, "mut sum = 1", 0));
    try t.expectEqual(Answer.other, try meaningAt(&compilation, &mut, 0, "mut sum)", 0));
}

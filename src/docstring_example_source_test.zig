//! Docstring extraction and typed display selection without native execution.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const examples = @import("docstring_example_source.zig");
const source = @import("source.zig");
const tests = @import("tests_index.zig");

const fixture =
    "public func value() -> str:\n" ++
    "    \"\"\"State, string, unit and ordinary displays.\n\n" ++
    "    >>> const number = 42\n" ++
    "    >>> value() # the comment stays outside the synthetic closing parenthesis\n    'hello'\n" ++
    "    >>> print(out, number)\n    42\n" ++
    "    >>> number\n    42\n" ++
    "    >>> b'hello'\n    b'hello'\n" ++
    "    >>> ''\n    ''\n" ++
    "    >>> for index in range(0, 1):\n    ...     _ = index\n" ++
    "    >>> -number + 1\n    -41\n" ++
    "    \"\"\"\n    return \"hello\"\n" ++
    "func main() -> int:\n    return 0\n";

test "docstring example source extracts only function docs and preserves ordinary no-example fast path" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "app.selka", fixture);
    const found = try examples.extract(a, "app", src);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqual(@as(usize, 8), found[0].examples.len);
    try t.expectEqualStrings("app::value.example", try examples.name(a, found[0]));
    try t.expectEqual(@as(usize, 4), found[0].examples[0].line);
    try t.expect(!try examples.contains(a, "# >>> ignored()\nfunc main() -> int:\n    return 0\n"));
    try t.expect(!try examples.contains(a, "\"\"\"Module prose\n>>> ignored()\n\"\"\"\n"));
    try t.expect(!try examples.contains(a, "this has no prompt and is not parsed"));
}

test "docstring example malformedTranscript retains syntax errors only with a transcript literal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expect(try examples.contains(a, fixture ++ "\npublic func malformed(\n"));
    try t.expect(!try examples.contains(a, "# >>> ignored()\npublic func malformed(\n"));
    try t.expect(try examples.contains(a, fixture ++ "\n$\n"));
    try t.expect(try examples.contains(a, "public func value() -> int:\n    \"\"\"An unfinished transcript.\n\n    >>> value()\n    42\n"));
    try t.expect(!try examples.contains(a, "public func value() -> int:\n    \"\"\"Nested prose is not a transcript.\n    prose\n      >>> value()\n      42\n"));
    try t.expect(!try examples.contains(a, "# >>> ignored()\npublic func value() -> int:\n    \"\"\"Unfinished prose only.\n"));
}

test "docstring example generated names avoid the complete declaration namespace" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const collision = "\nrecord test__docstring_example_value:\n    code: int\n" ++
        "func test__docstring_example_value_() -> bool:\n    return True\n";
    const src = try source.Source.init(a, "app.selka", fixture ++ collision);
    const block = (try examples.extract(a, "app", src))[0];
    try t.expectEqualStrings("test__docstring_example_value__", block.generated);
}

test "docstring example generated names avoid import aliases and facade bindings" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const alias = try source.Source.init(a, "app.selka", "import helper as test__docstring_example_value\n" ++ fixture);
    try t.expectEqualStrings("test__docstring_example_value_", (try examples.extract(a, "app", alias))[0].generated);
    const facade = try source.Source.init(a, "app.selka", "import helper\nexport helper.test__docstring_example_value\n" ++ fixture);
    try t.expectEqualStrings("test__docstring_example_value_", (try examples.extract(a, "app", facade))[0].generated);
}

fn expectOriginalPositions(program: compiler.typed.Program, length: usize) !void {
    for (program.nodes) |node| {
        try t.expect(node.span.start < length);
        switch (node.data) {
            .unary => |operation| try t.expect(operation.op_span.start < length),
            .binary => |operation| try t.expect(operation.op_span.start < length),
            else => {},
        }
    }
    for (program.statements) |statement| {
        try t.expect(statement.span.start < length);
        if (statement.data == .range_loop) for (statement.data.range_loop.parts) |part| try t.expect(part.binding.start < length);
    }
    for (program.functions) |function| for (function.scope.locals) |local| try t.expect(local.declaration.start < length);
}

const assignment_fixture =
    "record Point:\n" ++
    "    x: int\n\n\n" ++
    "public func update() -> int:\n" ++
    "    \"\"\"Assignments are statements, not displayed expressions.\n\n" ++
    "    >>> mut xs: int[] = [1]\n" ++
    "    >>> xs[0] = 2\n" ++
    "    >>> xs[0]\n    2\n" ++
    "    >>> mut p = Point(x=1)\n" ++
    "    >>> p.x = 2\n" ++
    "    >>> p.x\n    2\n" ++
    "    \"\"\"\n    return 0\n" ++
    "func main() -> int:\n    return 0\n";

// spec: DOCSTRING-EXAMPLE-1
test "FR-412 a single index or field assignment example is a statement, not a displayed expression" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "app.selka", assignment_fixture);
    const block = (try examples.extract(a, "app", src))[0];
    const transcript = try examples.transcriptOf(a, block);
    const probe = try examples.render(a, block, null, transcript);
    var unit = try compiler.Compilation.init(a, "app.selka", probe.text);
    defer unit.deinit();
    try unit.check();
    const display = try examples.displaysOf(a, unit.program.?, unit.src, block, probe);
    try t.expectEqualSlices(examples.Display, &.{ .statement, .statement, .printed, .statement, .statement, .printed }, display);
}

test "docstring example source probes typed repr unit statements and printed values then remaps positions" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "app.selka", fixture);
    const block = (try examples.extract(a, "app", src))[0];
    const transcript = try examples.transcriptOf(a, block);
    const probe = try examples.render(a, block, null, transcript);
    var unit = try compiler.Compilation.init(a, "app.selka", probe.text);
    defer unit.deinit();
    try unit.check();
    const display = try examples.displaysOf(a, unit.program.?, unit.src, block, probe);
    try t.expectEqualSlices(examples.Display, &.{ .statement, .repr, .unit, .printed, .repr, .repr, .statement, .printed }, display);
    const overlay = try examples.render(a, block, display, transcript);
    var final = try compiler.Compilation.init(a, "app.selka", overlay.text);
    defer final.deinit();
    try final.check();
    const remapped = try examples.remap(a, final.program.?, final.src, block, overlay);
    try expectOriginalPositions(remapped, block.src.bytes.len);
    const discovered = try tests.discoveredTests(a, remapped, &.{});
    try t.expectEqual(@as(usize, 1), discovered.len);
    try t.expectEqualStrings("app::value.example", remapped.functions[@backingInt(discovered[0])].name);
    try t.expectEqual(@as(usize, 4), final.src.locate(remapped.functions[@backingInt(discovered[0])].declaration.start).line);
    const message = try std.fmt.allocPrint(a, "app.selka:{d}:9: error[E_UNKNOWN_NAME]: unresolved", .{1 + std.mem.count(u8, overlay.text[0..overlay.expressions[1].start], "\n")});
    try t.expect(std.mem.startsWith(u8, try examples.diagnosticText(a, message, block, overlay), "app.selka:5:9:"));
}

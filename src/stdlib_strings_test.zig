//! Standard text helpers cover the operations the builtin str type does not provide.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-STRINGS-1
test "standard strings classify search trim pad and convert text at signed boundaries" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/strings.my"), 42);
}

// spec-case: STANDARD-STRINGS-1
test "standard float wrapper shares the pinned parser and stays noalloc" {
    try fixture.run(t.allocator,
        \\module main
        \\import strings
        \\
        \\
        \\def parse(text: str) -> int noalloc:
        \\    match strings.to_float(text):
        \\        case Some(value):
        \\            if value == 1000.5:
        \\                return 42
        \\            return 1
        \\        case None:
        \\            return 2
        \\
        \\
        \\def main() -> int:
        \\    if parse(" 1_000.5 ") != 42:
        \\        return 3
        \\    match strings.to_float("inf"):
        \\        case Some(value):
        \\            if value == 1.0 / 0.0:
        \\                return 42
        \\            return 4
        \\        case None:
        \\            return 5
    , 42);
}

// spec-case: STANDARD-STRINGS-1
test "standard string results survive collection at every managed allocation" {
    try fixture.stress(t.allocator, "module main\nimport strings\n" ++
        "def main() -> int:\n" ++
        "    total = 0\n" ++
        "    for line in strings.lines(\"a\\r\\nbb\\nccc\"):\n" ++
        "        total += len(strings.strip(line))\n" ++
        "    match strings.pad_left(strings.upper(\"ff\"), 4, \"0\"):\n" ++
        "        case Ok(text):\n" ++
        "            if text != \"00FF\":\n" ++
        "                return 1\n" ++
        "        case Err(_):\n" ++
        "            return 2\n" ++
        "    return total + 36\n", 42);
}

// spec-case: STDLIB-ERROR-UNION-1
test "standard strings error unions expose the category and message of a rejected builder" {
    try fixture.run(t.allocator,
        \\module main
        \\import strings
        \\
        \\
        \\def describe(produced: Result[str, strings.Error]) -> int:
        \\    match produced:
        \\        case Ok(_):
        \\            return 0
        \\        case Err(error):
        \\            match error:
        \\                case strings.Error.Invalid(detail):
        \\                    return len(detail)
        \\                case strings.Error.Overflow(detail):
        \\                    return 0 - len(detail)
        \\
        \\
        \\def main() -> int:
        \\    if describe(strings.repeat("a", 0 - 1)) != len("repeat count must not be negative"):
        \\        return 1
        \\    if describe(strings.pad_left("x", 2, " ")) != 0:
        \\        return 2
        \\    if describe(strings.format_float(1.0e30, 2)) >= 0:
        \\        return 3
        \\    return 42
    , 42);
}

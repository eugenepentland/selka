//! Standard text helpers cover the operations the builtin str type does not provide.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-STRINGS-1
test "standard strings classify search trim pad and convert text at signed boundaries" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/strings_fixture.selka"), 42);
}

// spec-case: STANDARD-STRINGS-1
test "standard float wrapper shares the pinned parser and stays noalloc" {
    try fixture.run(t.allocator,
        \\import strings
        \\
        \\
        \\@noalloc
        \\func parse(text: str) -> int:
        \\    match parse_float(text):
        \\        case Some(value):
        \\            if value == 1000.5:
        \\                return 42
        \\            return 1
        \\        case None:
        \\            return 2
        \\
        \\
        \\func main() -> int:
        \\    if parse(" 1_000.5 ") != 42:
        \\        return 3
        \\    match parse_float("inf"):
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
    try fixture.run(t.allocator, "import strings\n" ++
        "func main() -> int:\n" ++
        "    mut total = 0\n" ++
        "    for line in strings.lines(\"a\\r\\nbb\\nccc\"):\n" ++
        "        total += strings.char_count(strings.strip(line))\n" ++
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
        \\import strings
        \\
        \\
        \\func describe(produced: Result[str, strings.Error]) -> int:
        \\    match produced:
        \\        case Ok(_):
        \\            return 0
        \\        case Err(error):
        \\            match error:
        \\                case Invalid(value=detail):
        \\                    return strings.char_count(detail)
        \\                case Overflow(value=detail):
        \\                    return 0 - strings.char_count(detail)
        \\
        \\
        \\func main() -> int:
        \\    if describe(strings.pad_left("x", 2, "ab")) != strings.char_count("pad fill must be exactly one character"):
        \\        return 1
        \\    if describe(strings.pad_left("x", 2, " ")) != 0:
        \\        return 2
        \\    if describe(strings.format_float(1.0e30, 2)) >= 0:
        \\        return 3
        \\    return 42
    , 42);
}

// spec: STANDARD-FORMAT-FLOAT-EXACT-1
test "format_float rounds the exact binary value, not the rounded scaled product" {
    try fixture.run(t.allocator,
        \\import strings
        \\
        \\
        \\func text(produced: Result[str, strings.Error]) -> str:
        \\    match produced:
        \\        case Ok(rendered):
        \\            return copy(rendered)
        \\        case Err(_):
        \\            return "error"
        \\
        \\
        \\func main() -> int:
        \\    if text(strings.format_float(2.675, 2)) != "2.67":
        \\        return 1
        \\    if text(strings.format_float(0.0 - 8.345, 2)) != "-8.35":
        \\        return 2
        \\    if text(strings.format_float(1.005, 2)) != "1.00":
        \\        return 3
        \\    if text(strings.format_float(0.125, 2)) != "0.13":
        \\        return 4
        \\    if text(strings.format_float(2.5, 0)) != "3":
        \\        return 5
        \\    if text(strings.format_float(0.0 - 0.001, 2)) != "0.00":
        \\        return 6
        \\    return 42
    , 42);
}

// spec: STANDARD-STRINGS-3
test "standard strings builder accumulates borrowed text and preserves snapshots" {
    try fixture.run(t.allocator,
        \\import strings
        \\
        \\
        \\func first_field(text: str) -> str:
        \\    mut out = strings.builder()
        \\    mut index = 0
        \\    while index < strings.char_count(text) and strings.char_at(text, index) != ",":
        \\        strings.append(mut out, strings.char_at(text, index))
        \\        index += 1
        \\    return strings.finish(out)
        \\
        \\
        \\func main() -> int:
        \\    if first_field("a\"b,c") != "a\"b":
        \\        return 1
        \\    mut empty = strings.builder()
        \\    if strings.finish(empty) != "":
        \\        return 2
        \\    mut out = strings.builder()
        \\    strings.append(mut out, "a")
        \\    strings.append(mut out, "λ")
        \\    mut first = strings.finish(out)
        \\    strings.append(mut out, "b")
        \\    mut second = strings.finish(out)
        \\    if first != "aλ":
        \\        return 3
        \\    if second != "aλb":
        \\        return 4
        \\    return 42
    , 42);
}

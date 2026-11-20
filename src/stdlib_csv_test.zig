//! Standard CSV parses RFC 4180 rows and renders them back without a dialect option.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-CSV-1
test "standard csv parses quoted fields blank rows and positioned refusals" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/csv_fixture.selka"), 42);
}

// spec-case: STANDARD-CSV-1
test "standard csv error unions carry a matchable category and message" {
    try fixture.run(t.allocator,
        \\import strings
        \\import csv
        \\
        \\
        \\func main() -> int:
        \\    match csv.parse("\"a\n"):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(error):
        \\            match error:
        \\                case UnterminatedQuote(value=detail):
        \\                    if strings.char_count(detail) == 0:
        \\                        return 2
        \\                    return 42
        \\                case UnexpectedQuote(value=_):
        \\                    return 3
        \\                case UnexpectedCharacter(value=_):
        \\                    return 4
    , 42);
}

// spec-case: STANDARD-CSV-1
test "standard csv writer keeps a lone empty field distinct from a blank row" {
    try fixture.run(t.allocator,
        \\import csv
        \\
        \\
        \\func main() -> int:
        \\    if csv.write([[]]) != "\n":
        \\        return 1
        \\    if csv.write([[""]]) != "\"\"\n":
        \\        return 2
        \\    return 42
    , 42);
}

// spec-case: STANDARD-CSV-1
test "standard csv parse_fields keeps whether each field was quoted and refuses as parse does" {
    try fixture.run(t.allocator,
        \\import csv
        \\
        \\
        \\func quoted_of(text: str) -> bool[]:
        \\    mut flags: bool[] = []
        \\    match csv.parse_fields(text):
        \\        case Ok(rows):
        \\            for field in rows[0]:
        \\                append(mut flags, field.quoted)
        \\        case Err(_):
        \\            assert False
        \\    return flags
        \\
        \\
        \\func main() -> int:
        \\    if quoted_of("a,,b") != [False, False, False]:
        \\        return 1
        \\    if quoted_of("a,\"\",b") != [False, True, False]:
        \\        return 2
        \\    match csv.parse_fields("a\"b"):
        \\        case Ok(_):
        \\            return 3
        \\        case Err(error):
        \\            if csv.message(error) != "quote inside an unquoted field at line 1, column 2":
        \\                return 4
        \\    return 42
    , 42);
}

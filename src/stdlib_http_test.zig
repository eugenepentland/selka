//! Standard HTTP parses complete messages and renders them back without I/O.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-HTTP-1
test "standard http parses requests and responses and refuses malformed framing" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/http_fixture.selka"), 42);
}

// spec-case: STANDARD-HTTP-1
test "standard http header and error text answer borrows a program reads in place" {
    try fixture.run(t.allocator, "import csv\n" ++
        "import http\n" ++
        "func main() -> int:\n" ++
        "    const fields = [http.Header(name=\"Host\", value=\"example.test\")]\n" ++
        "    const found = http.header(fields, \"host\")\n" ++
        "    const failure = csv.Error.UnterminatedQuote(value=\"open quote\")\n" ++
        "    match found:\n" ++
        "        case Some(value):\n" ++
        "            return len(value) + len(csv.message(failure)) + 20\n" ++
        "        case None:\n" ++
        "            return 1\n", 42);
}

// spec-case: STANDARD-HTTP-1
test "standard message helpers answer their reason text, copied, for a program that keeps it" {
    try fixture.run(t.allocator, "import csv\n" ++
        "import http\n" ++
        "import strings\n" ++
        "func main() -> int:\n" ++
        "    const plain = strings.message(strings.Error.Invalid(value=\"open\"))\n" ++
        "    const quoted = csv.message(csv.Error.UnterminatedQuote(value=\"open quote\"))\n" ++
        "    const framed = http.message(http.Error.Malformed(value=\"bad\"))\n" ++
        "    return len(plain) + len(quoted) + len(framed) + 25\n", 42);
}

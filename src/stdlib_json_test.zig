//! Standard JSON parses strict RFC 8259 text and renders it back without whitespace.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-JSON-1
test "standard json parses renders navigates and rejects noncompliant documents" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/json.my"), 42);
}

// spec-case: STANDARD-JSON-1
test "standard json keeps parsed values rooted under collection stress" {
    try fixture.stress(t.allocator, "module main\nimport json\n" ++
        "def main() -> int:\n" ++
        "    source = \"{\\\"rows\\\":[{\\\"n\\\":40},{\\\"n\\\":2}]}\"\n" ++
        "    match json.loads(source):\n" ++
        "        case Ok(document):\n" ++
        "            if json.dumps(document) != source:\n" ++
        "                return 1\n" ++
        "            return total(document)\n" ++
        "        case Err(_):\n" ++
        "            return 2\n" ++
        "def total(document: json.Json) -> int:\n" ++
        "    match json.get(document, \"rows\"):\n" ++
        "        case Some(rows):\n" ++
        "            return summed(rows)\n" ++
        "        case None:\n" ++
        "            return 3\n" ++
        "def summed(rows: json.Json) -> int:\n" ++
        "    sum = 0\n" ++
        "    index = 0\n" ++
        "    while index < 2:\n" ++
        "        match json.at(rows, index):\n" ++
        "            case Some(row):\n" ++
        "                sum += field(row)\n" ++
        "            case None:\n" ++
        "                return 4\n" ++
        "        index += 1\n" ++
        "    return sum\n" ++
        "def field(row: json.Json) -> int:\n" ++
        "    match json.get(row, \"n\"):\n" ++
        "        case Some(value):\n" ++
        "            match json.as_int(value):\n" ++
        "                case Some(count):\n" ++
        "                    return count\n" ++
        "                case None:\n" ++
        "                    return 0\n" ++
        "        case None:\n" ++
        "            return 0\n", 42);
}

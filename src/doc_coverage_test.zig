//! Pure documentation contract tests, independent of compiler integration.
const std = @import("std");
const coverage = @import("doc_coverage.zig");
const testing = std.testing;
const page =
    "# Managed arenas\n\nIntro prose.\n\n```selka\n# doc: expect 42\nfunc main() -> int:\n    return 42\n```\n" ++
    "\n## Limits\n\nOnly prose here.\n\n## Running it\n\n```bash\nselka run main.selka\n```\n" ++
    "\n### Deeper\n\nNested prose.\n\n## Signatures\n\n```text\n# doc: not-selka\nfunc answer() -> int\n```\n";

// spec: DOCCOV-1
test "sections resolve by anchor and end at the next heading of the same or higher level" {
    const intro = coverage.section(page, "managed-arenas").?;
    try testing.expectEqual(@as(u8, 1), intro.level);
    try testing.expect(std.mem.indexOf(u8, intro.body, "Intro prose.") != null);
    // Level-2 headings are nested under a level-1 one, so they do not end its section.
    try testing.expect(std.mem.indexOf(u8, intro.body, "Only prose here.") != null);
    const limits = coverage.section(page, "limits").?;
    try testing.expectEqual(@as(u8, 2), limits.level);
    try testing.expect(std.mem.indexOf(u8, limits.body, "Only prose here.") != null);
    try testing.expect(std.mem.indexOf(u8, limits.body, "selka run main.selka") == null);
    const running = coverage.section(page, "running-it").?;
    try testing.expect(std.mem.indexOf(u8, running.body, "Nested prose.") != null);
    try testing.expect(std.mem.indexOf(u8, running.body, "# doc: not-selka") == null);
    try testing.expect(coverage.section(page, "absent-heading") == null);
}

// spec-case: DOCCOV-1
test "anchors lowercase words, drop punctuation and keep hyphens" {
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings("selka-build", coverage.anchor("`selka build`", &buffer));
    try testing.expectEqualStrings("what-selka-run-prints", coverage.anchor("What `selka run` prints", &buffer));
    try testing.expectEqualStrings("value-producing-matches", coverage.anchor("Value-producing matches", &buffer));
    var narrow: [4]u8 = undefined;
    try testing.expectEqualStrings("mana", coverage.anchor("Managed arenas", &narrow));
}

// spec-case: DOCCOV-1
test "a language section needs an executed example and a tooling section a command" {
    try testing.expect(coverage.hasRunnableExample(coverage.section(page, "managed-arenas").?.body));
    try testing.expect(!coverage.hasRunnableExample(coverage.section(page, "limits").?.body));
    try testing.expect(!coverage.hasRunnableExample(coverage.section(page, "running-it").?.body));
    try testing.expect(!coverage.hasRunnableExample(coverage.section(page, "signatures").?.body));
    try testing.expect(coverage.hasCommandExample(coverage.section(page, "running-it").?.body));
    try testing.expect(coverage.hasCommandExample(coverage.section(page, "signatures").?.body));
    try testing.expect(!coverage.hasCommandExample(coverage.section(page, "limits").?.body));
}

// spec-case: DOCCOV-1
test "a skipped or prose-tagged block is not an executed example" {
    try testing.expect(!coverage.hasRunnableExample("```selka\n# doc: skip fragment\nfunc main() -> int:\n    return 1\n```\n"));
    try testing.expect(coverage.hasRunnableExample("```selka\n\n# doc: check\nfunc answer() -> int:\n    return 1\n```\n"));
    try testing.expect(coverage.hasRunnableExample("~~~selka\nfunc main() -> int:\n    return 1\n~~~\n"));
    // There is no short tag, and the marker the language had before its rename still opts a block out.
    try testing.expect(!coverage.hasRunnableExample("```my\n\n# doc: check\nfunc answer() -> int:\n    return 1\n```\n")); // rename: keep
    try testing.expect(!coverage.hasRunnableExample("```selka\n# doc: not-mylang\nfunc answer() -> int:\n    return 1\n```\n")); // rename: keep
    try testing.expect(coverage.hasDirective("# doc: expect 42\nfunc main() -> int:\n    return 42\n", "expect"));
    try testing.expect(!coverage.hasDirective("func main() -> int:\n# doc: skip late\n    return 1\n", "skip"));
}

const module = "\n\n# Lowercase hexadecimal text.\npublic func encode(data: bytes) -> str:\n    return data.hex()\n\n\npublic func decode(text: str) -> bytes:\n    return text\n";

// spec: DOCCOV-2
test "standard exports are read from source and need a doc comment directly above" {
    var names = coverage.exports(module);
    try testing.expectEqualStrings("encode", names.next().?);
    try testing.expectEqualStrings("decode", names.next().?);
    try testing.expect(names.next() == null);
    try testing.expect(coverage.documentsExport(module, "encode"));
    try testing.expect(!coverage.documentsExport(module, "decode"));
    try testing.expect(!coverage.documentsExport(module, "absent"));
}

// spec-case: DOCCOV-2
test "an export counts as documented only when the section names it as a whole word" {
    const body = "`encode(data)` returns text. See encode_upper for the other case.\n";
    try testing.expect(coverage.mentions(body, "encode"));
    try testing.expect(coverage.mentions(body, "encode_upper"));
    try testing.expect(!coverage.mentions(body, "decode"));
    try testing.expect(!coverage.mentions("prefixencode", "encode"));
}

// spec-case: DOCCOV-2
test "result and resource definitions count as documented exports" {
    const source = "\n\n# One live stream.\npublic resource Connection: network\n\n\n# One acquisition result.\npublic result Connected:\n    ok: Connection,\n    err: int\n";
    try testing.expect(coverage.documentsExport(source, "Connection"));
    try testing.expect(coverage.documentsExport(source, "Connected"));
    try testing.expect(coverage.documentsExport(source, "absent") == false);
}

test "an attribute between an export's comment and its definition keeps it documented" {
    const source = "# A digest.\n@sealed\npublic record Digest:\n    w0: u64\n\n@sealed\npublic record Bare:\n    n: int\n";
    try testing.expect(coverage.documentsExport(source, "Digest"));
    try testing.expect(!coverage.documentsExport(source, "Bare"));
}

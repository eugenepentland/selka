//! Documentation-coverage rules over in-memory Markdown and guest source text.
//! The rules are pure text queries so the `doc-coverage` command and its unit
//! tests share exactly one implementation.
const std = @import("std");

/// Info-string tags whose fenced blocks the documentation runner executes.
pub const executable_tags = [_][]const u8{ "mylang", "my" };
/// Info-string tags that show a command or a transcript for a tooling feature.
pub const command_tags = [_][]const u8{ "bash", "sh", "console", "text" };
/// Source keywords that introduce a definition a standard module can export.
pub const definition_keywords = [_][]const u8{ "def", "class", "union", "enum", "type", "const" };

/// One fenced code block: its info string and the text between the fences.
pub const Fence = struct { info: []const u8, body: []const u8 };

/// A heading's level and the document text beneath it.
pub const Section = struct { level: u8, body: []const u8 };

const Heading = struct { level: u8, text: []const u8 };
const Marker = struct { char: u8, count: usize, info: []const u8 };

/// Walk the fenced code blocks of a Markdown fragment in document order.
pub const Fences = struct {
    rest: []const u8,
    /// The next fenced block, or null once the fragment is exhausted.
    pub fn next(self: *Fences) ?Fence {
        while (line(&self.rest)) |text| {
            const opened = marker(text) orelse continue;
            const start = self.rest;
            var length: usize = 0;
            while (line(&self.rest)) |inner| {
                if (closes(inner, opened)) return .{ .info = opened.info, .body = start[0..length] };
                length = start.len - self.rest.len;
            }
            return .{ .info = opened.info, .body = start[0..length] };
        }
        return null;
    }
};

/// Walk the `export NAME` declarations of a guest module source.
pub const Exports = struct {
    rest: []const u8,
    /// The next exported name, or null at the end of the source.
    pub fn next(self: *Exports) ?[]const u8 {
        while (line(&self.rest)) |text| {
            if (!std.mem.startsWith(u8, text, "export ")) continue;
            const name = std.mem.trim(u8, text[7..], " \t;");
            if (name.len != 0) return name;
        }
        return null;
    }
};

/// Start walking the fenced code blocks of `text`.
pub fn fences(text: []const u8) Fences {
    return .{ .rest = text };
}

/// Start walking the exported names declared by `source`.
pub fn exports(source: []const u8) Exports {
    return .{ .rest = source };
}

/// Write the GitHub-style heading anchor of `text` into `buffer`.
pub fn anchor(text: []const u8, buffer: []u8) []const u8 {
    var used: usize = 0;
    for (text) |character| {
        const kept = keep(character) orelse continue;
        if (used == buffer.len) return buffer[0..used];
        buffer[used] = kept;
        used += 1;
    }
    return buffer[0..used];
}

/// The section a `page.md#anchor` pointer names, or null when no heading matches it.
pub fn section(document: []const u8, wanted: []const u8) ?Section {
    var buffer: [256]u8 = undefined;
    var rest = document;
    var opened: ?Marker = null;
    var start: usize = 0;
    var level: u8 = 0;
    while (true) {
        const before = document.len - rest.len;
        const text = line(&rest) orelse break;
        const after = document.len - rest.len;
        if (opened) |open| {
            if (closes(text, open)) opened = null;
            continue;
        }
        if (marker(text)) |open| {
            opened = open;
            continue;
        }
        const found = heading(text) orelse continue;
        if (level != 0) {
            if (found.level <= level) return .{ .level = level, .body = document[start..before] };
            continue;
        }
        if (std.mem.eql(u8, anchor(found.text, &buffer), wanted)) {
            level = found.level;
            start = after;
        }
    }
    if (level != 0) return .{ .level = level, .body = document[start..] };
    return null;
}

/// Whether a section carries an example the documentation runner executes.
pub fn hasRunnableExample(body: []const u8) bool {
    var walk = fences(body);
    while (walk.next()) |fence| {
        if (!tagged(fence.info, &executable_tags)) continue;
        if (hasDirective(fence.body, "not-mylang")) continue;
        if (hasDirective(fence.body, "skip")) continue;
        return true;
    }
    return false;
}

/// Whether a section shows a command, a transcript, or a guest program.
pub fn hasCommandExample(body: []const u8) bool {
    var walk = fences(body);
    while (walk.next()) |fence| {
        if (tagged(fence.info, &command_tags)) return true;
        if (tagged(fence.info, &executable_tags)) return true;
    }
    return false;
}

/// Whether `name` appears in `body` as a whole word rather than inside a longer one.
pub fn mentions(body: []const u8, name: []const u8) bool {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, body, start, name)) |at| {
        start = at + 1;
        if (at != 0 and wordly(body[at - 1])) continue;
        const end = at + name.len;
        if (end != body.len and wordly(body[end])) continue;
        return true;
    }
    return false;
}

/// Whether the definition of `name` in `source` carries a `#` comment directly above it.
pub fn documentsExport(source: []const u8, name: []const u8) bool {
    var rest = source;
    var previous: []const u8 = "";
    while (line(&rest)) |text| {
        if (defines(text, name)) return std.mem.startsWith(u8, std.mem.trimStart(u8, previous, " \t"), "#");
        previous = text;
    }
    return false;
}

/// Whether a fenced block carries the leading `doc:` directive `name`.
pub fn hasDirective(body: []const u8, name: []const u8) bool {
    var rest = body;
    while (line(&rest)) |text| {
        if (std.mem.trim(u8, text, " \t").len == 0) continue;
        const found = directive(text) orelse return false;
        if (std.mem.eql(u8, found, name)) return true;
    }
    return false;
}

fn keep(character: u8) ?u8 {
    if (character == ' ') return '-';
    if (character == '-' or character == '_') return character;
    if (std.ascii.isAlphanumeric(character)) return std.ascii.toLower(character);
    return null;
}

fn wordly(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_';
}

fn line(rest: *[]const u8) ?[]const u8 {
    if (rest.len == 0) return null;
    const end = std.mem.indexOfScalar(u8, rest.*, '\n') orelse rest.len;
    const text = rest.*[0..end];
    rest.* = rest.*[@min(end + 1, rest.len)..];
    return std.mem.trimEnd(u8, text, "\r");
}

fn marker(text: []const u8) ?Marker {
    const trimmed = std.mem.trimStart(u8, text, " \t");
    if (trimmed.len < 3) return null;
    const character = trimmed[0];
    if (character != '`' and character != '~') return null;
    var count: usize = 0;
    while (count < trimmed.len and trimmed[count] == character) count += 1;
    if (count < 3) return null;
    return .{ .char = character, .count = count, .info = std.mem.trim(u8, trimmed[count..], " \t") };
}

fn closes(text: []const u8, opened: Marker) bool {
    const found = marker(text) orelse return false;
    return found.char == opened.char and found.count >= opened.count and found.info.len == 0;
}

fn heading(text: []const u8) ?Heading {
    var level: u8 = 0;
    while (level < text.len and text[level] == '#') level += 1;
    if (level == 0 or level > 6 or level == text.len) return null;
    if (text[level] != ' ' and text[level] != '\t') return null;
    const name = std.mem.trim(u8, text[level..], " \t#");
    if (name.len == 0) return null;
    return .{ .level = level, .text = name };
}

fn tagged(info: []const u8, names: []const []const u8) bool {
    const first = std.mem.sliceTo(info, ' ');
    for (names) |name| if (std.mem.eql(u8, first, name)) return true;
    return false;
}

fn directive(text: []const u8) ?[]const u8 {
    var rest = std.mem.trim(u8, text, " \t");
    if (std.mem.startsWith(u8, rest, "//")) {
        rest = rest[2..];
    } else if (std.mem.startsWith(u8, rest, "#")) {
        rest = rest[1..];
    } else return null;
    rest = std.mem.trimStart(u8, rest, " \t");
    if (!std.mem.startsWith(u8, rest, "doc:")) return null;
    rest = std.mem.trimStart(u8, rest[4..], " \t");
    var end: usize = 0;
    while (end < rest.len and (std.ascii.isAlphabetic(rest[end]) or rest[end] == '-')) end += 1;
    return rest[0..end];
}

fn defines(text: []const u8, name: []const u8) bool {
    for (definition_keywords) |keyword| {
        if (!std.mem.startsWith(u8, text, keyword)) continue;
        var rest = text[keyword.len..];
        if (rest.len == 0 or (rest[0] != ' ' and rest[0] != '\t')) continue;
        rest = std.mem.trimStart(u8, rest, " \t");
        if (!std.mem.startsWith(u8, rest, name)) continue;
        const after = rest[name.len..];
        if (after.len == 0 or !wordly(after[0])) return true;
    }
    return false;
}

const testing = std.testing;
const page =
    "# Managed arenas\n\nIntro prose.\n\n```mylang\n# doc: expect 42\ndef main() -> int:\n    return 42\n```\n" ++
    "\n## Limits\n\nOnly prose here.\n\n## Running it\n\n```bash\nmylang run main.my\n```\n" ++
    "\n### Deeper\n\nNested prose.\n\n## Signatures\n\n```text\n# doc: not-mylang\ndef answer() -> int\n```\n";

// spec: DOCCOV-1
test "sections resolve by anchor and end at the next heading of the same or higher level" {
    const intro = section(page, "managed-arenas").?;
    try testing.expectEqual(@as(u8, 1), intro.level);
    try testing.expect(std.mem.indexOf(u8, intro.body, "Intro prose.") != null);
    // Level-2 headings are nested under a level-1 one, so they do not end its section.
    try testing.expect(std.mem.indexOf(u8, intro.body, "Only prose here.") != null);
    const limits = section(page, "limits").?;
    try testing.expectEqual(@as(u8, 2), limits.level);
    try testing.expect(std.mem.indexOf(u8, limits.body, "Only prose here.") != null);
    try testing.expect(std.mem.indexOf(u8, limits.body, "mylang run main.my") == null);
    const running = section(page, "running-it").?;
    try testing.expect(std.mem.indexOf(u8, running.body, "Nested prose.") != null);
    try testing.expect(std.mem.indexOf(u8, running.body, "# doc: not-mylang") == null);
    try testing.expect(section(page, "absent-heading") == null);
}

// spec-case: DOCCOV-1
test "anchors lowercase words, drop punctuation and keep hyphens" {
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings("mylang-build", anchor("`mylang build`", &buffer));
    try testing.expectEqualStrings("what-mylang-run-prints", anchor("What `mylang run` prints", &buffer));
    try testing.expectEqualStrings("value-producing-matches", anchor("Value-producing matches", &buffer));
    var narrow: [4]u8 = undefined;
    try testing.expectEqualStrings("mana", anchor("Managed arenas", &narrow));
}

// spec-case: DOCCOV-1
test "a language section needs an executed example and a tooling section a command" {
    try testing.expect(hasRunnableExample(section(page, "managed-arenas").?.body));
    try testing.expect(!hasRunnableExample(section(page, "limits").?.body));
    try testing.expect(!hasRunnableExample(section(page, "running-it").?.body));
    try testing.expect(!hasRunnableExample(section(page, "signatures").?.body));
    try testing.expect(hasCommandExample(section(page, "running-it").?.body));
    try testing.expect(hasCommandExample(section(page, "signatures").?.body));
    try testing.expect(!hasCommandExample(section(page, "limits").?.body));
}

// spec-case: DOCCOV-1
test "a skipped or prose-tagged block is not an executed example" {
    try testing.expect(!hasRunnableExample("```mylang\n# doc: skip fragment\ndef main() -> int:\n    return 1\n```\n"));
    try testing.expect(hasRunnableExample("```my\n\n# doc: check\ndef answer() -> int:\n    return 1\n```\n"));
    try testing.expect(hasRunnableExample("~~~mylang\ndef main() -> int:\n    return 1\n~~~\n"));
    try testing.expect(hasDirective("// doc: expect 42\nfn main() -> i64 { return 42; }\n", "expect"));
    try testing.expect(!hasDirective("def main() -> int:\n# doc: skip late\n    return 1\n", "skip"));
}

const module = "module hex\nexport encode\nexport decode\n\n\n# Lowercase hexadecimal text.\ndef encode(data: bytes) -> str:\n    return data.hex()\n\n\ndef decode(text: str) -> bytes:\n    return text\n";

// spec: DOCCOV-2
test "standard exports are read from source and need a doc comment directly above" {
    var names = exports(module);
    try testing.expectEqualStrings("encode", names.next().?);
    try testing.expectEqualStrings("decode", names.next().?);
    try testing.expect(names.next() == null);
    try testing.expect(documentsExport(module, "encode"));
    try testing.expect(!documentsExport(module, "decode"));
    try testing.expect(!documentsExport(module, "absent"));
}

// spec-case: DOCCOV-2
test "an export counts as documented only when the section names it as a whole word" {
    const body = "`encode(data)` returns text. See encode_upper for the other case.\n";
    try testing.expect(mentions(body, "encode"));
    try testing.expect(mentions(body, "encode_upper"));
    try testing.expect(!mentions(body, "decode"));
    try testing.expect(!mentions("prefixencode", "encode"));
}

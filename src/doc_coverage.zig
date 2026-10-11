//! Documentation-coverage rules over in-memory Markdown and guest source text.
//! The rules are pure text queries so the `doc-coverage` command and its unit
//! tests share exactly one implementation.
const std = @import("std");

/// Info-string tags whose fenced blocks the documentation runner executes.
pub const executable_tags = [_][]const u8{ "mylang", "my" };
/// Info-string tags that show a command or a transcript for a tooling feature.
pub const command_tags = [_][]const u8{ "bash", "sh", "console", "text" };
/// Source keywords that introduce a definition a standard module can export.
pub const definition_keywords = [_][]const u8{ "func", "record", "enum", "type", "const", "result", "resource" };

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

/// Walk the published declarations of a guest module source. A standard module
/// publishes a declaration with the `public` modifier; a legacy `export NAME`
/// directive is still recognized so the walker keeps reading older fixtures.
pub const Exports = struct {
    rest: []const u8,
    /// The next published name, or null at the end of the source.
    pub fn next(self: *Exports) ?[]const u8 {
        while (line(&self.rest)) |text| {
            if (std.mem.startsWith(u8, text, "export ")) {
                const name = std.mem.trim(u8, text[7..], " \t;");
                if (name.len != 0) return name;
                continue;
            }
            if (publishedName(text)) |name| return name;
        }
        return null;
    }
};

/// The name a `public` definition line publishes, or null when the line is not
/// one. Only a published definition is an export the documentation must cover.
fn publishedName(text: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, text, "public ")) return null;
    return definitionName(text);
}

/// The name a definition line declares, looking through an optional leading
/// `public` modifier. Null when the line is not a definition.
fn definitionName(text: []const u8) ?[]const u8 {
    var rest = text;
    if (std.mem.startsWith(u8, rest, "public ")) rest = rest["public ".len..];
    for (definition_keywords) |keyword| {
        if (!std.mem.startsWith(u8, rest, keyword)) continue;
        var after = rest[keyword.len..];
        if (after.len == 0 or (after[0] != ' ' and after[0] != '\t')) continue;
        after = std.mem.trimStart(u8, after, " \t");
        var end: usize = 0;
        while (end < after.len and wordly(after[end])) end += 1;
        if (end == 0) return null;
        return after[0..end];
    }
    return null;
}

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
    const declared = definitionName(text) orelse return false;
    return std.mem.eql(u8, declared, name);
}

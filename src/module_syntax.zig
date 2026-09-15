//! Identify source that opens as a module project rather than a single-file unit.
const std = @import("std");

/// Whether `bytes` begins with a module, import, or export directive that names
/// a module. Leading blank lines and whole-line comments are skipped. Anything
/// else - including assignments spelling `module`, `import`, or `export` - is a
/// single-file program.
pub fn usesModuleSyntax(bytes: []const u8) bool {
    var cursor: usize = 0;
    while (true) {
        while (cursor < bytes.len and std.ascii.isWhitespace(bytes[cursor])) cursor += 1;
        if (cursor >= bytes.len or bytes[cursor] != '#') break;
        while (cursor < bytes.len and bytes[cursor] != '\n') cursor += 1;
    }
    const start = cursor;
    while (cursor < bytes.len and (std.ascii.isAlphanumeric(bytes[cursor]) or bytes[cursor] == '_')) cursor += 1;
    const keyword = bytes[start..cursor];
    if (!std.mem.eql(u8, keyword, "module")) {
        if (!std.mem.eql(u8, keyword, "import")) {
            if (!std.mem.eql(u8, keyword, "export")) return false;
        }
    }
    while (cursor < bytes.len and (bytes[cursor] == ' ' or bytes[cursor] == '\t')) cursor += 1;
    if (cursor >= bytes.len) return false;
    const next = bytes[cursor];
    return std.ascii.isAlphabetic(next) or next == '_';
}

// spec: ARGV-1
test "module syntax detection ignores comments and rejects assignment lookalikes" {
    try std.testing.expect(usesModuleSyntax("module app\n"));
    try std.testing.expect(usesModuleSyntax("\n# note\nimport helper\n"));
    try std.testing.expect(usesModuleSyntax("export value\n"));
    try std.testing.expect(!usesModuleSyntax("module = 1\n"));
    try std.testing.expect(!usesModuleSyntax("import = 2\n"));
    try std.testing.expect(!usesModuleSyntax("def main() -> int:\n    return 0\n"));
    try std.testing.expect(!usesModuleSyntax(""));
}

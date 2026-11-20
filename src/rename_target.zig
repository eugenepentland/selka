//! How `selka rename` is told what to rename (decision D-FR3-1): the spellings the tools already print.
//!
//! - `module::name` names a module-level declaration: a function, a constant, a record, enum, union, domain or alias type,
//!   a constraint. `module::Type.member` names a record field or an enum case (or union variant), and
//!   `module::Type.Case.field` a named field of a case: the identities `selka index-project` prints. The call-site
//!   spelling `module.name` (`shapes.Point.x`) is accepted too, as `index-project --symbol` accepts it.
//! - `FILE:LINE:COLUMN` names whatever the identifier at that one-based position declares or uses: the only spelling a
//!   parameter or a local has, and one any other kind accepts.
//! - `hiding:NAME` names every local, parameter or pattern binding of the project spelled `NAME` in a module where `NAME`
//!   is a module-level name or an import alias: every binding `E_SHADOWING` refuses for hiding `NAME` (decision D-FR18-1).
//!
//! The new name must be a plain identifier that is not a reserved word.
const std = @import("std");
const lexer = @import("lexer.zig");

/// One parsed target.
pub const Spelling = union(enum) {
    /// `FILE:LINE:COLUMN`, one-based.
    position: Position,
    /// `module::name`, `module::Type.member`, or the call-site spelling `module.name`.
    qualified: []const u8,
    /// `hiding:NAME`: every binding that hides the module-level name or import alias `NAME` of its module.
    hiding: []const u8,
};

/// The prefix of the spelling that names every binding hiding one name.
pub const hiding_prefix = "hiding:";

/// A one-based position in a file.
pub const Position = struct { path: []const u8, line: usize, column: usize };

/// Parse a target, or null when it is neither spelling.
pub fn parse(target: []const u8) ?Spelling {
    if (target.len == 0) return null;
    if (position(target)) |found| return .{ .position = found };
    if (std.mem.startsWith(u8, target, hiding_prefix)) {
        const name = target[hiding_prefix.len..];
        if (name.len == 0 or !dottedNames(name) or std.mem.indexOfScalar(u8, name, '.') != null) return null;
        return .{ .hiding = name };
    }
    if (std.mem.indexOf(u8, target, "::")) |split| {
        if (split == 0 or split + 2 >= target.len) return null;
        if (std.mem.indexOf(u8, target[split + 2 ..], "::") != null) return null;
        if (!dottedNames(target[0..split]) or !dottedNames(target[split + 2 ..])) return null;
        return .{ .qualified = target };
    }
    if (std.mem.indexOfScalar(u8, target, '.') == null or !dottedNames(target)) return null;
    return .{ .qualified = target };
}

/// The name a qualified spelling ends with: what the declaration is called now.
pub fn lastName(qualified: []const u8) []const u8 {
    const tail = if (std.mem.lastIndexOf(u8, qualified, "::")) |split| qualified[split + 2 ..] else qualified;
    const dot = std.mem.lastIndexOfScalar(u8, tail, '.') orelse return tail;
    return tail[dot + 1 ..];
}

/// `FILE:LINE:COLUMN`: two positive numbers after the last two colons, and a path before them.
fn position(target: []const u8) ?Position {
    const last = std.mem.lastIndexOfScalar(u8, target, ':') orelse return null;
    const middle = std.mem.lastIndexOfScalar(u8, target[0..last], ':') orelse return null;
    if (middle == 0 or target[middle - 1] == ':') return null;
    const line = std.fmt.parseInt(usize, target[middle + 1 .. last], 10) catch return null;
    const column = std.fmt.parseInt(usize, target[last + 1 ..], 10) catch return null;
    if (line == 0 or column == 0) return null;
    return .{ .path = target[0..middle], .line = line, .column = column };
}

fn dottedNames(text: []const u8) bool {
    var parts = std.mem.splitScalar(u8, text, '.');
    while (parts.next()) |part| {
        if (part.len == 0 or !(std.ascii.isAlphabetic(part[0]) or part[0] == '_')) return false;
        for (part[1..]) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    }
    return true;
}

/// Why a new name cannot be written, or null when it can.
pub const NameProblem = enum { not_identifier, reserved_word };

/// Check the new name's spelling: a plain identifier that is no reserved word.
pub fn checkName(name: []const u8) ?NameProblem {
    if (!dottedNames(name) or std.mem.indexOfScalar(u8, name, '.') != null) return .not_identifier;
    if (!lexer.isIdentifier(name)) return .reserved_word;
    return null;
}

/// Which tokens of a file other than the declaring one can be a use of the target, by where the grammar lets such a use
/// stand (D-FR3-9): a module-level declaration is named there only qualified (`alias.name`, `export alias.name`); a
/// parameter only as a call's label (`f(name=...)`); a field or a case only after a `.`, as a label (`Row(name=...)`,
/// `case c(name=x)`) or in a pattern (`case c(name)`, `x is name`). Every other token there names something else, and
/// the declaring file's tokens are all candidates.
pub const Filter = enum {
    all,
    qualified,
    labels,
    members,

    /// Whether the occurrence of `length` bytes at `start` of `bytes` stands where this filter admits a use.
    pub fn admits(self: Filter, bytes: []const u8, start: usize, length: usize) bool {
        return switch (self) {
            .all => true,
            .qualified => afterDot(bytes, start),
            .labels => beforeEquals(bytes, start + length),
            .members => afterDot(bytes, start) or beforeEquals(bytes, start + length) or inPattern(bytes, start),
        };
    }
};

/// Whether a `.` comes right before `start`, spaces aside.
pub fn afterDot(bytes: []const u8, start: usize) bool {
    var at = start;
    while (at > 0 and (bytes[at - 1] == ' ' or bytes[at - 1] == '\t')) at -= 1;
    return at > 0 and bytes[at - 1] == '.';
}

/// Whether one `=` (not `==`) comes right after `end`, spaces aside.
pub fn beforeEquals(bytes: []const u8, end: usize) bool {
    var at = end;
    while (at < bytes.len and (bytes[at] == ' ' or bytes[at] == '\t')) at += 1;
    return at < bytes.len and bytes[at] == '=' and (at + 1 >= bytes.len or bytes[at + 1] != '=');
}

/// Whether `start` is on a line that opens with `case`, or after an ` is ` on its line: a pattern.
pub fn inPattern(bytes: []const u8, start: usize) bool {
    const line_start = if (std.mem.lastIndexOfScalar(u8, bytes[0..start], '\n')) |at| at + 1 else 0;
    const before = bytes[line_start..start];
    const trimmed = std.mem.trimStart(u8, before, " \t");
    if (std.mem.startsWith(u8, trimmed, "case ")) return true;
    return std.mem.indexOf(u8, before, " is ") != null;
}

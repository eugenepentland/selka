//! B2: a module function needs its module's `import`, and the certain repair is
//! the import line itself.
//!
//! The check already knows which module a call names; what it needs is where the
//! directive goes. `placement` reads the checked unit's own bytes: a leading
//! comment block stays at the top, the directives form one block after it, and a
//! blank line separates them from the first declaration. A project check maps
//! that offset back to the declaring module before publishing the fix, so
//! `selka fix` edits the file the call is written in.
const std = @import("std");
const product = @import("product.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// The code a call to a module function without its import reports.
pub const code = "E_MODULE_NOT_IMPORTED";

/// Where a missing directive belongs: the offset after the last existing
/// directive (or after the leading comment block when there is none), and
/// whether the insert needs its own blank line before the code that follows.
pub const Placement = struct {
    offset: usize,
    blank_after: bool,
};

/// The placement a missing `import` directive belongs at, in the canonical
/// layout: leading comments, the directive block in sorted order, one blank
/// line, declarations. `module` is the directive's own name, so the new line
/// joins the block where the formatter would keep it.
pub fn placement(bytes: []const u8, module: []const u8) Placement {
    var cursor: usize = 0;
    // A module's leading comment block stays above the directives, and the
    // blank lines inside it disappear once a directive joins it.
    var comments_end: ?usize = null;
    while (cursor < bytes.len) {
        const line = lineAt(bytes, cursor);
        if (line.text.len == 0) {
            cursor = line.after;
            continue;
        }
        if (startsImport(line.text) or !std.mem.startsWith(u8, line.text, "#")) break;
        comments_end = line.after;
        cursor = line.after;
    }
    var directives_end: ?usize = null;
    while (cursor < bytes.len) {
        const line = lineAt(bytes, cursor);
        if (startsImport(line.text)) {
            // The block is sorted, so the new directive goes before the first one
            // whose name follows it.
            const start = directNameStart(line.text) orelse break;
            const name_text = line.text[start..];
            const end = std.mem.indexOfAny(u8, name_text, " \t;") orelse name_text.len;
            if (std.mem.order(u8, module, name_text[0..end]) == .lt) return .{ .offset = cursor, .blank_after = false };
            directives_end = line.after;
        } else if (line.text.len != 0 or directives_end == null) break;
        cursor = line.after;
    }
    const at = directives_end orelse comments_end orelse 0;
    const rest = lineAt(bytes, at);
    return .{ .offset = at, .blank_after = at >= bytes.len or rest.text.len != 0 };
}

/// The offset of a directive's own module name on one `import` line.
fn directNameStart(text: []const u8) ?usize {
    if (!startsImport(text)) return null;
    var at: usize = "import ".len;
    while (at < text.len and (text[at] == ' ' or text[at] == '\t')) at += 1;
    return if (at < text.len) at else null;
}

/// One line as trimmed text and the offset just past its newline.
const Line = struct { text: []const u8, after: usize };

fn lineAt(bytes: []const u8, from: usize) Line {
    const end = std.mem.indexOfScalarPos(u8, bytes, from, '\n') orelse bytes.len;
    return .{
        .text = std.mem.trim(u8, bytes[from..end], " \t\r"),
        .after = if (end < bytes.len) end + 1 else end,
    };
}

/// Whether one source line opens an `import` directive.
fn startsImport(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, "import ")) return false;
    const rest = std.mem.trim(u8, line["import ".len..], " \t");
    if (rest.len == 0) return false;
    return std.ascii.isAlphabetic(rest[0]) or rest[0] == '_';
}

/// Whether the unit's own `import` directives bind `module`, read from the
/// directive block the same way `placement` does. A directive is the whole
/// evidence: the checker's unit has no module graph to ask.
pub fn importsModule(bytes: []const u8, module: []const u8) bool {
    var cursor: usize = 0;
    while (cursor < bytes.len) {
        const line = lineAt(bytes, cursor);
        if (startsImport(line.text)) {
            const rest = std.mem.trim(u8, line.text["import ".len..], " \t");
            const end = std.mem.indexOfAny(u8, rest, " \t;") orelse rest.len;
            if (std.mem.eql(u8, rest[0..end], module)) return true;
        } else if (endsDirectives(line.text)) {
            return false;
        }
        cursor = line.after;
    }
    return false;
}

/// Whether one line ends the directive block: any line that is neither blank nor
/// a comment.
fn endsDirectives(text: []const u8) bool {
    if (text.len == 0) return false;
    if (std.mem.startsWith(u8, text, "#")) return false;
    if (std.mem.startsWith(u8, text, "import ")) return false;
    return true;
}

/// Whether `name` is the name of a standard module, which a file reaches only through its `import` line.
pub fn standardModule(name: []const u8) bool {
    for (@import("standard_library.zig").paths) |path| {
        if (path.len == name.len + product.source_suffix.len and std.mem.startsWith(u8, path, name) and product.isSource(path)) return true;
    }
    return false;
}

/// The message for a qualified name `module.member` whose standard module the file does not import: a program that
/// wrote `text.encode()` needed no import, and its function form `strings.encode(text)` does (W13-S5).
pub fn unimportedMessage(allocator: std.mem.Allocator, module: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "`{s}` is a standard module that this file does not import; add `import {s}`", .{ module, module });
}

/// The message for a qualified name `written.member` whose module is a file of this project that the file does not import
/// (FR32), as `unimportedMessage` words it for a standard module. `module` is the dotted name the `import` writes: `written`
/// itself, or the longer path of a module in a directory (`calc` for `shared.calc`).
pub fn unimportedProjectMessage(allocator: std.mem.Allocator, written: []const u8, module: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.eql(u8, written, module)) return std.fmt.allocPrint(allocator, "`{s}` is a module of this project that this file does not import; add `import {s}`", .{ module, module });
    return std.fmt.allocPrint(allocator, "`{s}` is the module `{s}` of this project, which this file does not import; add `import {s}`", .{ written, module, module });
}

/// The diagnostic message for a call whose module is not imported.
pub fn message(allocator: std.mem.Allocator, call: []const u8, module: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "`{s}` is a module function, so this unit needs `import {s}`", .{ call, module });
}

/// The certain repair: the whole `import` line at `where`, with the blank line
/// the canonical layout needs when a declaration follows it directly.
pub fn edit(allocator: std.mem.Allocator, where: Placement, module: []const u8) std.mem.Allocator.Error!diagnostic.Edit {
    const line = if (where.blank_after)
        try std.fmt.allocPrint(allocator, "import {s}\n\n", .{module})
    else
        try std.fmt.allocPrint(allocator, "import {s}\n", .{module});
    return .{ .span = .{ .start = where.offset, .end = where.offset }, .text = line };
}

/// The `import` line a standard module needs in the unit `span` belongs to, or null
/// when that unit already imports it. `src` is the checked source: a merged project
/// maps the span back to its own unit, and the edit is mapped onto the merged text.
pub fn moduleEdit(allocator: std.mem.Allocator, src: source.Source, span: source.Span, module: []const u8) (std.mem.Allocator.Error || error{InternalError})!?diagnostic.Edit {
    const mapped = src.origins.len != 0;
    var input: usize = 0;
    if (mapped) {
        const original = src.originalSpan(span) catch return error.InternalError;
        input = original.input;
    }
    const bytes = if (mapped) src.origins[input].original.bytes else src.bytes;
    if (importsModule(bytes, module)) return null;
    const where = placement(bytes, module);
    var found = try edit(allocator, where, module);
    if (mapped) found.span = src.mappedSpan(input, .{ .start = where.offset, .end = where.offset }) catch return error.InternalError;
    return found;
}

/// The whole source line of one import statement, newline included, when the
/// line holds that statement and nothing else but an optional comment; null
/// for any other layout, so a fix never deletes a neighbouring statement.
pub fn importLine(bytes: []const u8, name: source.Span) ?source.Span {
    const start = if (std.mem.lastIndexOfScalar(u8, bytes[0..name.start], '\n')) |newline| newline + 1 else 0;
    const newline = std.mem.indexOfScalarPos(u8, bytes, name.end, '\n');
    const end = if (newline) |at| at + 1 else bytes.len;
    const head = std.mem.trimEnd(u8, bytes[start..name.start], " \t");
    if (!std.mem.eql(u8, head, "import")) return null;
    const tail = std.mem.trim(u8, bytes[name.end .. newline orelse bytes.len], " \t\r");
    if (tail.len != 0 and tail[0] != '#' and !validAlias(tail)) return null;
    return .{ .start = start, .end = end };
}
/// Whether an import line's text after its module name is `as ALIAS`,
/// optionally followed by a comment.
fn validAlias(tail: []const u8) bool {
    if (!std.mem.startsWith(u8, tail, "as ")) return false;
    const rest = std.mem.trimStart(u8, tail["as ".len..], " \t");
    var end: usize = 0;
    while (end < rest.len and (std.ascii.isAlphanumeric(rest[end]) or rest[end] == '_')) end += 1;
    if (end == 0) return false;
    const after = std.mem.trim(u8, rest[end..], " \t");
    return after.len == 0 or after[0] == '#';
}

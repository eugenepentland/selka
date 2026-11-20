//! Diagnostics of a docstring example's overlay check, restated against the
//! docstring they came from.
//!
//! `selka test` compiles an example inside a function appended to its module
//! (`docstring_example_source.zig`), so a check of that overlay reports bytes of
//! the generated text. This file reads the `diagnostic-v1` lines such a check
//! publishes and writes each error again against the original source: the
//! location names the prompt line (the exact bytes when the generated text
//! copies them), and a structured `fix` survives only when every edit maps
//! exactly onto bytes the docstring holds (`originalRange`). A repair that does
//! not map is dropped and the diagnostic says so; it is never guessed, so
//! `selka fix` applies an edit to a docstring only where it is certain.
const std = @import("std");
const source = @import("source.zig");
const examples = @import("docstring_example_source.zig");
const diagnostic_output = @import("diagnostic_output.zig");

/// What restating can fail with.
pub const Error = std.mem.Allocator.Error;

/// One example block and the overlay a check of it read.
pub const Overlaid = struct { block: examples.Block, overlay: examples.Overlay };

/// What restating one overlay check's report found.
pub const Tally = struct {
    /// Error diagnostics written to the output.
    errors: usize = 0,
    /// Errors whose structured repair could not be mapped into the docstring.
    unmapped: usize = 0,
};

/// The note an error carries when its repair could not be mapped.
pub const unmapped_note = "the repair edits text the docstring example does not hold verbatim, so no edit is offered; change the example by hand";

const Value = std.json.Value;
const version = "diagnostic-v1";

/// Append the errors of one overlay check `report` (`diagnostic-v1` lines) to
/// `out`, located in the docstring, as JSON lines or as terminal text. A warning
/// is dropped, as `selka test` shows none for an example. An error located
/// outside the generated function keeps its location (the overlay copies the
/// module's own text unchanged), but its notes and edits that name the generated
/// function are restated all the same: a declaration's rename also renames its
/// uses in the example. Such an error that names nothing generated, and any line
/// that is not a diagnostic, passes through unchanged. Every error's repair is
/// kept only when all its edits map exactly.
pub fn restate(a: std.mem.Allocator, out: *std.ArrayList(u8), at: Overlaid, report: []const u8, format: diagnostic_output.Format) Error!Tally {
    var tally: Tally = .{};
    var lines = std.mem.splitScalar(u8, report, '\n');
    while (lines.next()) |raw| {
        if (raw.len == 0) continue;
        var root = std.json.parseFromSliceLeaky(Value, a, raw, .{}) catch {
            try out.print(a, "{s}\n", .{raw});
            continue;
        };
        const diag = diagnosticOf(&root) orelse {
            try out.print(a, "{s}\n", .{raw});
            continue;
        };
        if (!std.mem.eql(u8, text(diag, "severity") orelse "", "error")) continue;
        const location = diag.object.getPtr("location") orelse {
            try out.print(a, "{s}\n", .{raw});
            continue;
        };
        const located = try restateLocation(a, at, location);
        if (!located and !namesGenerated(at, diag)) {
            try out.print(a, "{s}\n", .{raw});
            continue;
        }
        try restateNotes(a, at, diag);
        const mapped = try restateFix(a, at, diag, location);
        if (located) {
            tally.errors += 1;
            if (!mapped) tally.unmapped += 1;
        }
        if (format == .text and (located or moduleText(at, location))) {
            try writeText(a, out, at.block, diag);
            continue;
        }
        try out.appendSlice(a, try std.json.Stringify.valueAlloc(a, root, .{}));
        try out.append(a, '\n');
    }
    return tally;
}

/// The `diagnostic` object of a parsed `diagnostic-v1` diagnostic line.
fn diagnosticOf(root: *Value) ?*Value {
    if (root.* != .object) return null;
    const kind = text(root, "version") orelse return null;
    if (!std.mem.eql(u8, kind, version)) return null;
    const diag = root.object.getPtr("diagnostic") orelse return null;
    return if (diag.* == .object) diag else null;
}

/// A string field of a JSON object.
fn text(object: *const Value, name: []const u8) ?[]const u8 {
    const field = object.object.get(name) orelse return null;
    return if (field == .string) field.string else null;
}

/// A nonnegative integer field of a JSON object.
fn number(object: *const Value, name: []const u8) ?usize {
    const field = object.object.get(name) orelse return null;
    return if (field == .integer and field.integer >= 0) @intCast(field.integer) else null;
}

/// The byte span of a location, or of an edit, when it is an object with `bytes`.
fn spanOf(holder: *const Value) ?source.Span {
    if (holder.* != .object) return null;
    const bytes = holder.object.getPtr("bytes") orelse return null;
    if (bytes.* != .object) return null;
    return .{ .start = number(bytes, "start") orelse return null, .end = number(bytes, "end") orelse return null };
}

/// Rewrite a location that lies in this module's generated function to the
/// docstring: the exact bytes it copies, else the whole prompt line it was made
/// from. False, with the location untouched, for any other location.
fn restateLocation(a: std.mem.Allocator, at: Overlaid, location: *Value) Error!bool {
    if (location.* != .object) return false;
    if (!std.mem.eql(u8, text(location, "path") orelse return false, at.block.src.path)) return false;
    const span = spanOf(location) orelse return false;
    if (span.start < examples.appendedStart(at.overlay) or span.start > span.end) return false;
    const found = examples.originalRange(at.block, at.overlay, span) orelse examples.originalLine(at.overlay, span.start) orelse return false;
    const first = at.block.src.locate(found.start);
    const last = at.block.src.locate(found.end);
    try location.object.put(a, "start", try position(a, first));
    try location.object.put(a, "end", try position(a, last));
    var bytes: std.json.ObjectMap = .empty;
    try bytes.put(a, "start", .{ .integer = @intCast(found.start) });
    try bytes.put(a, "end", .{ .integer = @intCast(found.end) });
    try location.object.put(a, "bytes", .{ .object = bytes });
    return true;
}

/// Whether a note or an edit of `diag` names bytes of this module's generated function.
fn namesGenerated(at: Overlaid, diag: *const Value) bool {
    const start = examples.appendedStart(at.overlay);
    if (diag.object.get("notes")) |notes| if (notes == .array) for (notes.array.items) |note| {
        if (note != .object) continue;
        const location = note.object.get("location") orelse continue;
        if (inGenerated(at, &location, start)) return true;
    };
    const fix = diag.object.get("fix") orelse return false;
    if (fix != .object) return false;
    const edits = fix.object.get("edits") orelse return false;
    if (edits != .array) return false;
    for (edits.array.items) |edit| if (inGenerated(at, &edit, start)) return true;
    return false;
}

/// Whether a location or an edit of this module ends past `start`, the generated function's first byte.
fn inGenerated(at: Overlaid, holder: *const Value, start: usize) bool {
    if (holder.* != .object) return false;
    if (!std.mem.eql(u8, text(holder, "path") orelse return false, at.block.src.path)) return false;
    const span = spanOf(holder) orelse return false;
    return span.end > start;
}

/// Whether a location lies in this module's own text, before the generated
/// function: the overlay copies those bytes unchanged, so it stands as it is.
fn moduleText(at: Overlaid, location: *const Value) bool {
    if (location.* != .object) return false;
    if (!std.mem.eql(u8, text(location, "path") orelse return false, at.block.src.path)) return false;
    const span = spanOf(location) orelse return false;
    return span.start <= span.end and span.end <= examples.appendedStart(at.overlay);
}

fn position(a: std.mem.Allocator, place: source.Source.Location) Error!Value {
    var object: std.json.ObjectMap = .empty;
    try object.put(a, "line", .{ .integer = @intCast(place.line) });
    try object.put(a, "column", .{ .integer = @intCast(place.column) });
    return .{ .object = object };
}

/// Restate each note that points into this module's generated function.
fn restateNotes(a: std.mem.Allocator, at: Overlaid, diag: *Value) Error!void {
    const notes = diag.object.getPtr("notes") orelse return;
    if (notes.* != .array) return;
    for (notes.array.items) |*note| {
        if (note.* != .object) continue;
        const location = note.object.getPtr("location") orelse continue;
        _ = try restateLocation(a, at, location);
    }
}

/// Keep the diagnostic's repair when every edit maps exactly into the docstring,
/// else drop it and add the note saying why. False when a repair was dropped.
fn restateFix(a: std.mem.Allocator, at: Overlaid, diag: *Value, location: *const Value) Error!bool {
    const fix = diag.object.getPtr("fix") orelse return true;
    if (mapEdits(a, at, fix)) return true;
    _ = diag.object.orderedRemove("fix");
    var note: std.json.ObjectMap = .empty;
    try note.put(a, "role", .{ .string = "related" });
    try note.put(a, "message", .{ .string = unmapped_note });
    try note.put(a, "location", location.*);
    const notes = diag.object.getPtr("notes") orelse {
        var created = std.json.Array.init(a);
        try created.append(.{ .object = note });
        try diag.object.put(a, "notes", .{ .array = created });
        return false;
    };
    if (notes.* == .array) try notes.array.append(.{ .object = note });
    return false;
}

/// Rewrite every edit of a `fix` from generated bytes to the docstring's bytes.
/// An edit in another module, or in this module's text before the generated
/// function, already names original bytes and stays as it is. False when any
/// other edit cannot be mapped exactly or its text would not survive a docstring;
/// the edits are then left half rewritten and the caller drops them all.
fn mapEdits(a: std.mem.Allocator, at: Overlaid, fix: *Value) bool {
    if (fix.* != .object) return false;
    const edits = fix.object.getPtr("edits") orelse return false;
    if (edits.* != .array or edits.array.items.len == 0) return false;
    for (edits.array.items) |*edit| {
        if (edit.* != .object) return false;
        const span = spanOf(edit) orelse return false;
        const own = std.mem.eql(u8, text(edit, "path") orelse return false, at.block.src.path);
        if (!own or span.end <= examples.appendedStart(at.overlay)) continue;
        if (!inlineText(text(edit, "text") orelse return false)) return false;
        const found = examples.originalRange(at.block, at.overlay, span) orelse return false;
        var bytes: std.json.ObjectMap = .empty;
        bytes.put(a, "start", .{ .integer = @intCast(found.start) }) catch return false;
        bytes.put(a, "end", .{ .integer = @intCast(found.end) }) catch return false;
        edit.object.put(a, "bytes", .{ .object = bytes }) catch return false;
    }
    return true;
}

/// Whether replacement text can sit inside one docstring line without changing
/// the transcript's shape: no line break (a new line would need its own prompt),
/// no backslash and no triple quote (either could change where the docstring ends).
fn inlineText(replacement: []const u8) bool {
    return std.mem.indexOfAny(u8, replacement, "\r\n\\") == null and
        std.mem.indexOf(u8, replacement, "\"\"\"") == null and
        std.mem.indexOf(u8, replacement, "'''") == null;
}

/// Terminal text for a restated diagnostic, in the layout of `Diagnostic.render`:
/// the primary line with its source line and caret, then the rule, notes and frames.
fn writeText(a: std.mem.Allocator, out: *std.ArrayList(u8), block: examples.Block, diag: *const Value) Error!void {
    const location = diag.object.get("location").?;
    const start = spanOf(&location).?.start;
    const place = block.src.locate(start);
    try out.print(a, "{s}:{d}:{d}: {s}[{s}]: {s}\n  {s}\n  ", .{
        place.path, place.line, place.column, text(diag, "severity") orelse "error", text(diag, "code") orelse "", text(diag, "message") orelse "", place.text,
    });
    for (0..place.column - 1) |index| try out.append(a, if (index < place.text.len and place.text[index] == '\t') '\t' else ' ');
    try out.appendSlice(a, "^\n");
    if (text(diag, "rule")) |rule| try out.print(a, "  note: ownership rule {s}\n", .{rule});
    const notes = diag.object.get("notes") orelse return;
    if (notes != .array) return;
    for (notes.array.items) |note| {
        if (note != .object) continue;
        const message = text(&note, "message") orelse continue;
        const role = text(&note, "role") orelse "related";
        if (std.mem.eql(u8, role, "alternative")) {
            if (!std.mem.eql(u8, message, text(diag, "message") orelse "")) try out.print(a, "  alternative: {s}\n", .{message});
        } else if (std.mem.eql(u8, role, "signature")) {
            try out.print(a, "  signature: {s}\n", .{message});
        } else if (note.object.get("location")) |where| {
            const start_at = where.object.get("start") orelse continue;
            if (start_at != .object) continue;
            try out.print(a, "  note: {s}:{d}:{d}: {s}\n", .{ text(&where, "path") orelse "", number(&start_at, "line") orelse 0, number(&start_at, "column") orelse 0, message });
        }
    }
}

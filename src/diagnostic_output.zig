//! Versioned diagnostic records resolve source coordinates before JSON serialization.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const project = @import("project.zig");
/// Default terminal text or one versioned JSON object per line.
pub const Format = enum { text, json };
const version = "diagnostic-v1";
const Position = struct { line: usize, column: usize };
const Location = struct { path: []const u8, start: Position, end: ?Position, bytes: ?source.Span };
const Note = struct { role: enum { related, origin, requirement }, message: []const u8, location: Location };
const Frame = struct { function: []const u8, location: Location };
const Payload = struct {
    code: []const u8,
    severity: []const u8,
    message: []const u8,
    location: Location,
    notes: []const Note,
    stack: struct { frames: []const Frame, omitted: usize },
};
fn location(src: source.Source, span: source.Span) Location {
    const start = src.locate(span.start);
    var result: Location = .{ .path = start.path, .start = .{ .line = start.line, .column = start.column }, .end = null, .bytes = null };
    var original = src;
    var range = span;
    if (src.origins.len != 0) {
        const mapped = src.originalSpan(span) catch return result;
        original = src.origins[mapped.input].original;
        range = mapped.span;
    }
    if (range.start > range.end or range.end > original.bytes.len) return result;
    const end = original.locate(range.end);
    result.end = .{ .line = end.line, .column = end.column };
    result.bytes = range;
    return result;
}
fn encode(allocator: std.mem.Allocator, value: anytype) std.mem.Allocator.Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    std.json.Stringify.value(value, .{}, &out.writer) catch return error.OutOfMemory;
    out.writer.writeByte('\n') catch return error.OutOfMemory;
    return out.toOwnedSlice();
}
fn payload(diag: diagnostic.Diagnostic, src: source.Source) Payload {
    return .{
        .code = diag.code,
        .severity = if (diag.severity == .err) "error" else "warning",
        .message = diag.message,
        .location = location(src, diag.span),
        .notes = &.{},
        .stack = .{ .frames = &.{}, .omitted = diag.stack.omitted },
    };
}
/// Allocate one source diagnostic, preserving notes and bounded guest frames.
pub fn render(allocator: std.mem.Allocator, diag: diagnostic.Diagnostic, src: source.Source, format: Format) std.mem.Allocator.Error![]u8 {
    if (format == .text) return diag.render(allocator, src);
    var notes: [3]Note = undefined;
    var count: usize = 0;
    for ([_]?diagnostic.Related{ diag.related, diag.provenance.origin, diag.provenance.requirement }, [_]@FieldType(Note, "role"){ .related, .origin, .requirement }) |entry, role| if (entry) |note| {
        notes[count] = .{ .role = role, .message = note.message, .location = location(src, note.span) };
        count += 1;
    };
    var frames: [16]Frame = undefined;
    for (diag.stack.frames[0..diag.stack.len], 0..) |frame, index| frames[index] = .{ .function = frame.function, .location = location(src, frame.span) };
    var data = payload(diag, src);
    data.notes = notes[0..count];
    data.stack.frames = frames[0..diag.stack.len];
    return encode(allocator, .{ .version = version, .kind = "diagnostic", .diagnostic = data });
}
/// Render module discovery/interface errors without losing cross-module related sites.
pub fn renderProject(allocator: std.mem.Allocator, loaded: *project.Project, format: Format) project.RenderProblemError![]u8 {
    if (format == .text) return loaded.renderProblem(allocator);
    const problem = loaded.problem orelse return error.NoProblem;
    var data = payload(.{ .code = problem.code, .message = problem.message, .span = problem.site.span }, loaded.modules.items[problem.site.module].src);
    var notes: [1]Note = undefined;
    if (problem.related) |related| {
        notes[0] = .{ .role = .related, .message = "related module/import declaration", .location = location(loaded.modules.items[related.module].src, related.span) };
        data.notes = &notes;
    }
    return encode(allocator, .{ .version = version, .kind = "diagnostic", .diagnostic = data });
}
/// Preserve auxiliary CLI messages as distinct records rather than mixing raw text into JSON.
pub fn message(allocator: std.mem.Allocator, text: []const u8, format: Format) std.mem.Allocator.Error![]u8 {
    if (format == .text) return allocator.dupe(u8, text);
    return encode(allocator, .{ .version = version, .kind = "message", .message = text });
}

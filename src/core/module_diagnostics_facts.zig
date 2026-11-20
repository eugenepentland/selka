//! A project's diagnostics grouped by module, each in the module's own coordinates (spec §17.8, G-D6): every diagnostic carries
//! (module, local span), and so does everything it points at, its `related` notes and its fix edits included. The `module-passes`
//! kind publishes the lines of a module as its `warnings` part, and `program-diagnostics` assembles what `check` prints from them.
//!
//! A line is `severity code start-end message`, followed by one ` | ` field for each thing the diagnostic points at: a note
//! (`related`, `origin`, `requirement`) as its role, module path, local span and message, a fix edit as its module path, local
//! span and replacement text, and the ownership rule. The path is the project-relative path of the module the span is in, so a
//! diagnostic that points into another module names that module, and a record that holds it must read that module's text.
const std = @import("std");
const language = @import("selka");
const diagnostic = language.diagnostic;

/// One module's diagnostics: its lines in the front end's order, and the paths of the other modules the lines point into.
pub const Located = struct { lines: []const []const u8, foreign: []const []const u8 };

const Mapped = struct { path: []const u8, start: usize, end: usize };

/// What locating a span needs: the merged source and the project's modules.
const Where = struct { src: language.source.Source, modules: []const language.project.Module };

fn locate(where: Where, span: language.source.Span) ?Mapped {
    const original = where.src.originalSpan(span) catch return null;
    if (original.input >= where.modules.len) return null;
    return .{ .path = where.modules[original.input].src.path, .start = original.span.start, .end = original.span.end };
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Append the ` | ` field for a note, noting a foreign path.
fn note(a: std.mem.Allocator, text: *std.ArrayList(u8), foreign: *std.ArrayList([]const u8), own: []const u8, where: Where, found: diagnostic.Related) std.mem.Allocator.Error!void {
    const at = locate(where, found.span) orelse return text.print(a, " | {s} unmapped {s}", .{ @tagName(found.role), found.message });
    try text.print(a, " | {s} {s}:{d}-{d} {s}", .{ @tagName(found.role), at.path, at.start, at.end, found.message });
    if (!std.mem.eql(u8, at.path, own)) try addPath(a, foreign, at.path);
}

fn addPath(a: std.mem.Allocator, list: *std.ArrayList([]const u8), path: []const u8) std.mem.Allocator.Error!void {
    for (list.items) |known| if (std.mem.eql(u8, known, path)) return;
    try list.append(a, path);
}

/// The diagnostics `items` (in the front end's order) of the project whose modules are `modules`, grouped by the module of their
/// primary span. Everything is allocated in `a`, which should be an arena.
pub fn group(a: std.mem.Allocator, src: language.source.Source, modules: []const language.project.Module, items: []const diagnostic.Diagnostic) std.mem.Allocator.Error![]const Located {
    const where: Where = .{ .src = src, .modules = modules };
    const lines = try a.alloc(std.ArrayList([]const u8), modules.len);
    const foreign = try a.alloc(std.ArrayList([]const u8), modules.len);
    @memset(lines, .empty);
    @memset(foreign, .empty);
    for (items) |item| {
        const original = src.originalSpan(item.span) catch continue;
        if (original.input >= modules.len) continue;
        const own = modules[original.input].src.path;
        var text: std.ArrayList(u8) = .empty;
        try text.print(a, "{s} {s} {d}-{d} {s}", .{ @tagName(item.severity), item.code, original.span.start, original.span.end, item.message });
        for (item.notes()) |maybe| {
            if (maybe) |found| try note(a, &text, &foreign[original.input], own, where, found);
        }
        if (item.provenance.fix) |fix| {
            for (0..fix.count()) |position| {
                const edit = fix.at(position);
                const at = locate(where, edit.span) orelse continue;
                try text.print(a, " | fix {s}:{d}-{d} {s}", .{ at.path, at.start, at.end, edit.text });
                if (!std.mem.eql(u8, at.path, own)) try addPath(a, &foreign[original.input], at.path);
            }
        }
        if (item.provenance.rule) |rule| try text.print(a, " | rule {s}", .{@tagName(rule)});
        if (item.provenance.obligation != null) try text.appendSlice(a, " | obligation");
        try lines[original.input].append(a, text.items);
    }
    const out = try a.alloc(Located, modules.len);
    for (out, lines, foreign) |*slot, module_lines, module_foreign| {
        std.mem.sort([]const u8, module_foreign.items, {}, lessThan);
        slot.* = .{ .lines = module_lines.items, .foreign = module_foreign.items };
    }
    return out;
}

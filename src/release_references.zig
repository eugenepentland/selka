//! Qualified whole-code-span references in current project prose.
const std = @import("std");
const context_module = @import("release_context.zig");
const Context = context_module.Context;
const decisions = @import("release_decisions.zig");
const transcripts = @import("docstring_examples.zig");
/// Declaration parsing and selected documentation I/O failures.
pub const Error = context_module.Error || @import("overview_store.zig").Error || @import("project.zig").LoadError || @import("interfaces.zig").ContractError;
/// Validate current docstrings, pending prose, README and selected docs pages.
pub fn check(context: Context) Error!void {
    for (context.model.modules) |id| {
        const module = context.model.project.modules.items[id];
        for (context.model.index.units[id].syntax.docstrings) |doc| {
            const raw = module.src.bytes[doc.span.start..doc.span.end];
            const width: usize = if (std.mem.startsWith(u8, raw, "\"\"\"") or std.mem.startsWith(u8, raw, "'''")) 3 else 1;
            const at = module.src.locate(doc.span.start + width);
            const text = raw[width .. raw.len - width];
            const examples = try transcripts.parse(context.allocator(), text, at.line);
            try scan(context, .{ .path = module.src.path, .line = at.line, .column = at.column }, text, examples);
        }
    }
    for (context.metadata.decisions) |decision| {
        if (!decision.pending) continue;
        try scan(context, .{ .path = decision.path }, decision.body, &.{});
    }
    for (try context_module.files(context, .markdown)) |path| {
        const bytes = (try @import("overview_store.zig").readOptional(context.allocator(), context.process.io, context.model.root, path)) orelse return error.HostIo;
        try scan(context, .{ .path = path }, bytes, &.{});
    }
}
const Position = @import("release_report.zig").Position;
fn scan(context: Context, origin: Position, bytes: []const u8, examples: []const transcripts.Example) !void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var line = origin.line;
    var fence: ?Fence = null;
    while (lines.next()) |raw| : (line += 1) {
        if (transcriptLine(examples, line)) continue;
        const trimmed = std.mem.trimStart(u8, raw, " \t");
        if (fence) |opened| {
            if (opened.closes(trimmed)) fence = null;
            continue;
        }
        if (Fence.open(trimmed)) |opened| {
            fence = opened;
            continue;
        }
        var offset: usize = 0;
        while (offset < raw.len) {
            if (raw[offset] != '`' or escaped(raw, offset)) {
                offset += 1;
                continue;
            }
            const start = offset;
            while (offset < raw.len and raw[offset] == '`') offset += 1;
            const width = offset - start;
            const content = offset;
            var end: ?usize = null;
            while (offset < raw.len) {
                if (raw[offset] != '`') {
                    offset += 1;
                    continue;
                }
                const close = offset;
                while (offset < raw.len and raw[offset] == '`') offset += 1;
                if (offset - close == width) {
                    end = close;
                    break;
                }
            }
            const name = raw[content .. end orelse break];
            if (!decisions.qualifiedName(name)) continue;
            if (try resolves(context, name)) continue;
            const location: Position = .{ .path = origin.path, .line = line, .column = content + 1 + (if (line == origin.line) origin.column - 1 else 0) };
            const message = try std.fmt.allocPrint(context.allocator(), "inline reference `{s}` names no current project or standard-library declaration", .{name});
            try context.report.at("E_RELEASE_REFERENCE_UNKNOWN", location, message);
        }
    }
}
const Fence = struct {
    character: u8,
    width: usize,
    fn open(line: []const u8) ?Fence {
        if (line.len < 3 or (line[0] != '`' and line[0] != '~')) return null;
        var width: usize = 0;
        while (width < line.len and line[width] == line[0]) width += 1;
        return if (width >= 3) .{ .character = line[0], .width = width } else null;
    }
    fn closes(self: Fence, line: []const u8) bool {
        const found = open(line) orelse return false;
        return found.character == self.character and found.width >= self.width and std.mem.trim(u8, line[found.width..], " \t\r").len == 0;
    }
};
fn resolves(context: Context, name: []const u8) !bool {
    const split = std.mem.indexOf(u8, name, "::").?;
    for (context.model.modules) |id| {
        const module = context.model.project.modules.items[id];
        if (!std.mem.eql(u8, module.name, name[0..split])) continue;
        return context.model.index.units[id].names.contains(name[split + 2 ..]);
    }
    const a = context.allocator();
    const path = try std.fmt.allocPrint(a, "{s}.selka", .{name[0..split]});
    if (@import("standard_library.zig").source(path) == null) return false;
    var project = @import("project.zig").Project.init(a);
    defer project.deinit();
    try project.load(.{ .context = null, .read = noProjectFile }, name[0..split], .{});
    const index = try @import("interfaces.zig").build(&project);
    const id = project.names.get(name[0..split]) orelse return false;
    const symbol = index.units[id].names.get(name[split + 2 ..]) orelse return false;
    return index.units[id].symbols.items[symbol].exported;
}
fn noProjectFile(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: usize) @import("project.zig").ReadError![]u8 {
    return error.NotFound;
}

fn escaped(bytes: []const u8, offset: usize) bool {
    var start = offset;
    while (start != 0 and bytes[start - 1] == '\\') start -= 1;
    return (offset - start) % 2 != 0;
}

fn transcriptLine(examples: []const transcripts.Example, line: usize) bool {
    for (examples) |example| {
        const last = example.lines[example.lines.len - 1].line + std.mem.count(u8, example.expected, "\n");
        if (line >= example.line and line <= last) return true;
    }
    return false;
}

test "release transcript prose exclusion follows continuation and expected output lines" {
    const t = std.testing;
    const text = "Opening prose.\n    >>> first()\n    ... second()\n    'expected `literal::name`'\n\n    Later `prose::name`.\n";
    const examples = try transcripts.parse(t.allocator, text, 10);
    defer transcripts.release(t.allocator, examples);
    try t.expect(!transcriptLine(examples, 10));
    try t.expect(transcriptLine(examples, 11));
    try t.expect(transcriptLine(examples, 12));
    try t.expect(transcriptLine(examples, 13));
    try t.expect(!transcriptLine(examples, 14));
    try t.expect(!transcriptLine(examples, 15));
}

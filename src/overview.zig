//! Public collection, rendering and file operations for checked project overviews.
//!
//! One generator produces two shapes: the summary `OVERVIEW.md` and one
//! `reference/<module>.md` per module. `--check` compares both, and a repair
//! rewrites both, including removing a reference whose module is gone.
const std = @import("std");
const loader = @import("release_project_load.zig");
const store = @import("overview_store.zig");
const paths = @import("overview_paths.zig");
const files = @import("interface_files.zig");
const types = @import("overview_types.zig");

/// Failures in declarations, release metadata or overview file I/O.
pub const Error = store.Error || files.Error;

/// Complete stable fact document used by Markdown and JSON consumers.
pub const Document = types.Document;
/// Collect declaration and release facts into the caller's arena.
pub const collect = @import("overview_collect.zig").collect;
/// Render already-collected facts without reading the filesystem.
pub const renderDocument = @import("overview_render.zig").render;
/// Render one module's reference from already-collected facts.
pub const renderReference = @import("overview_render.zig").renderReference;
/// Whether a generated line states only an empty fact; K1's predicate.
pub const noneFact = @import("overview_render.zig").noneFact;

/// One module's generated reference file: its root-relative path and bytes.
pub const Reference = struct { path: []const u8, markdown: []u8 };

/// Both generated shapes from one fact collection; every buffer is owned.
pub const Rendered = struct {
    markdown: []u8,
    references: []Reference,

    /// Release the summary, every path and every reference body.
    pub fn deinit(self: Rendered, a: std.mem.Allocator) void {
        a.free(self.markdown);
        for (self.references) |item| {
            a.free(item.path);
            a.free(item.markdown);
        }
        a.free(self.references);
    }
};

/// File comparison with caller-owned generated Markdown, every reference and a
/// bounded diff.
pub const Outcome = struct {
    current: bool,
    markdown: []u8,
    diff: []u8,
    stale: usize,

    /// Release both owned output buffers.
    pub fn deinit(self: Outcome, a: std.mem.Allocator) void {
        a.free(self.markdown);
        a.free(self.diff);
    }
};

/// Render the summary and every reference; returned bytes belong to the caller.
pub fn render(a: std.mem.Allocator, model: *loader.Model, metadata: store.Store) Error!Rendered {
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    return renderDocumentSet(a, try collect(arena, model, metadata));
}

/// Render both outputs from one already-collected fact document.
pub fn renderDocumentSet(a: std.mem.Allocator, document: Document) Error!Rendered {
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const markdown = try a.dupe(u8, try renderDocument(arena, document));
    errdefer a.free(markdown);
    const references = try a.alloc(Reference, document.modules.len);
    var built: usize = 0;
    errdefer {
        for (references[0..built]) |item| {
            a.free(item.path);
            a.free(item.markdown);
        }
        a.free(references);
    }
    for (document.modules, 0..) |module, index| {
        const path = try a.dupe(u8, try paths.referencePath(arena, document.releases.overview_path, module.name));
        errdefer a.free(path);
        references[index] = .{ .path = path, .markdown = try a.dupe(u8, try renderReference(arena, document, module)) };
        built = index + 1;
    }
    return .{ .markdown = markdown, .references = references };
}

/// Compare the configured summary and every reference without writing.
pub fn check(a: std.mem.Allocator, io: std.Io, model: *loader.Model) Error!Outcome {
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const scratch = arena_state.allocator();
    const metadata = try store.load(scratch, io, model);
    const rendered = try render(scratch, model, metadata);
    return compare(a, io, model, rendered);
}

/// Compare already-rendered bytes; this avoids collecting twice for JSON commands.
pub fn compare(a: std.mem.Allocator, io: std.Io, model: *const loader.Model, rendered: Rendered) Error!Outcome {
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const scratch = arena_state.allocator();
    var diff: std.ArrayList(u8) = .empty;
    var stale: usize = 0;
    const old = try store.readOptional(scratch, io, model.root, model.options.overview);
    if (old) |bytes| {
        if (!std.mem.eql(u8, bytes, rendered.markdown)) {
            stale += 1;
            try diff.appendSlice(scratch, try files.unifiedDiff(scratch, model.options.overview, bytes, rendered.markdown, 60));
        }
    } else {
        stale += 1;
        try diff.appendSlice(scratch, try files.unifiedDiff(scratch, model.options.overview, "", rendered.markdown, 60));
    }
    for (rendered.references) |item| {
        const previous = try store.readOptional(scratch, io, model.root, item.path);
        if (previous) |bytes| {
            if (std.mem.eql(u8, bytes, item.markdown)) continue;
            try diff.appendSlice(scratch, try files.unifiedDiff(scratch, item.path, bytes, item.markdown, 60));
        } else try diff.appendSlice(scratch, try files.unifiedDiff(scratch, item.path, "", item.markdown, 60));
        stale += 1;
    }
    for (try referenceFiles(scratch, io, model.root, model.options.overview)) |path| {
        if (declared(rendered, path)) continue;
        const bytes = (try store.readOptional(scratch, io, model.root, path)) orelse continue;
        stale += 1;
        try diff.appendSlice(scratch, try files.unifiedDiff(scratch, path, bytes, "", 60));
    }
    return .{
        .current = stale == 0,
        .markdown = try a.dupe(u8, rendered.markdown),
        .diff = try boundedDiff(a, diff.items),
        .stale = stale,
    };
}

/// Regenerate and write the summary and every reference only when bytes differ.
pub fn write(a: std.mem.Allocator, io: std.Io, model: *loader.Model) Error!Outcome {
    var outcome = try check(a, io, model);
    errdefer outcome.deinit(a);
    if (!outcome.current) {
        var arena_state = std.heap.ArenaAllocator.init(a);
        defer arena_state.deinit();
        const scratch = arena_state.allocator();
        const metadata = try store.load(scratch, io, model);
        try writeRendered(scratch, io, model, try render(scratch, model, metadata));
    }
    outcome.current = true;
    return outcome;
}

/// Persist one rendered set: the summary, every reference, and the removal of
/// a reference file whose module no longer exists.
pub fn writeRendered(a: std.mem.Allocator, io: std.Io, model: *const loader.Model, rendered: Rendered) Error!void {
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const scratch = arena_state.allocator();
    try writeFileAt(scratch, io, model.root, model.options.overview, rendered.markdown);
    for (rendered.references) |item| try writeFileAt(scratch, io, model.root, item.path, item.markdown);
    for (try referenceFiles(scratch, io, model.root, model.options.overview)) |path| {
        if (declared(rendered, path)) continue;
        const absolute = try std.fs.path.join(scratch, &.{ model.root, path });
        std.Io.Dir.cwd().deleteFile(io, absolute) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return error.HostIo,
        };
    }
}

fn declared(rendered: Rendered, path: []const u8) bool {
    for (rendered.references) |item| if (std.mem.eql(u8, item.path, path)) return true;
    return false;
}

fn writeFileAt(a: std.mem.Allocator, io: std.Io, root: []const u8, path: []const u8, bytes: []const u8) Error!void {
    const absolute = try std.fs.path.join(a, &.{ root, path });
    if (std.fs.path.dirname(absolute)) |parent| std.Io.Dir.cwd().createDirPath(io, parent) catch return error.HostIo;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = absolute, .data = bytes }) catch return error.HostIo;
}

fn referenceFiles(a: std.mem.Allocator, io: std.Io, root: []const u8, overview_path: []const u8) Error![]const []const u8 {
    const directory = try paths.referenceDirectory(a, overview_path);
    const absolute = try std.fs.path.join(a, &.{ root, directory });
    var dir = std.Io.Dir.cwd().openDir(io, absolute, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return error.HostIo,
    };
    defer dir.close(io);
    var iterator = dir.iterate();
    var result: std.ArrayList([]const u8) = .empty;
    while (iterator.next(io) catch return error.HostIo) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".md")) continue;
        try result.append(a, try std.fs.path.join(a, &.{ directory, entry.name }));
    }
    std.mem.sort([]const u8, result.items, {}, lexicalLess);
    return result.items;
}

fn lexicalLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn boundedDiff(a: std.mem.Allocator, text: []const u8) Error![]u8 {
    var lines: usize = 0;
    for (text, 0..) |byte, offset| {
        if (byte != '\n') continue;
        lines += 1;
        if (lines == 59 and offset + 1 < text.len) return std.mem.concat(a, u8, &.{ text[0 .. offset + 1], "... diff truncated at 60 lines\n" });
    }
    return a.dupe(u8, text);
}

//! CLI host for the shared declaration-only project overview, and for its HTML project page.
const std = @import("std");
const loader = @import("release_project_load.zig");
const overview = @import("overview.zig");
const overview_types = @import("overview_types.zig");
const store = @import("overview_store.zig");
const notes = @import("overview_notes.zig");
const review_html = @import("review_html.zig");
const usage =
    "usage: selka overview PROJECT (--write | --check) [--json]\n" ++
    "       selka overview PROJECT --html FILE [--data FILE] [--back HREF]\n";

/// What the command does: check the generated Markdown, write it, or write the project page.
const Mode = enum { check, write, html };

/// Parsed arguments. `html`, `data` and `back` belong to the project page, and `json` to check and write.
const Options = struct {
    project: []const u8,
    mode: Mode,
    json: bool = false,
    html: ?[]const u8 = null,
    data: ?[]const u8 = null,
    back: ?[]const u8 = null,
};

/// Run the overview command, returning 1 for staleness and 2 for usage/host errors.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    return command(process, args) catch |err| {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "selka overview: {s}\n", .{@errorName(err)}) catch "selka overview: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return switch (err) {
            error.SourceError, error.IncompleteProject => 1,
            else => 2,
        };
    };
}

fn command(process: std.process.Init, args: []const []const u8) !u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(process.io, usage);
        return 0;
    }
    const options = parse(args) orelse {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    };
    const a = process.arena.allocator();
    var source: loader.Failure = .{};
    var model = loader.loadWith(process.gpa, process.io, options.project, &source) catch |err| {
        if (err != error.SourceError or !source.present) return err;
        const line = try std.fmt.allocPrint(a, "{s}:{d}:{d}: error[{s}]: {s}\n", .{ source.path, source.line, source.column, source.code, source.message });
        try std.Io.File.stderr().writeStreamingAll(process.io, line);
        try std.Io.File.stderr().writeStreamingAll(process.io, try source.ruleNote(a));
        return 1;
    };
    defer model.deinit();
    const metadata = try store.load(a, process.io, &model);
    const document = try overview.collect(a, &model, metadata);
    if (options.html) |page| return writePage(process, a, &model, document, options, page);
    const rendered = try overview.renderDocumentSet(a, document);
    const outcome = try overview.compare(a, process.io, &model, rendered);
    const write = options.mode == .write;
    if (write and !outcome.current) try overview.writeRendered(a, process.io, &model, rendered);
    const current = write or outcome.current;
    var report: std.ArrayList(u8) = .empty;
    if (options.json) {
        try report.appendSlice(a, try std.json.Stringify.valueAlloc(a, .{
            .version = "overview-v1",
            .mode = if (write) "write" else "check",
            .status = if (current) "current" else "stale",
            .path = model.options.overview,
            .content = document,
            .markdown = rendered.markdown,
            .references = rendered.references,
            .diff = if (current) "" else outcome.diff,
        }, .{}));
        try report.append(a, '\n');
    } else if (current) {
        try report.print(a, "overview: {s} {s}\n", .{ if (write and !outcome.current) "wrote" else "current", model.options.overview });
    } else {
        try report.appendSlice(a, outcome.diff);
        try report.print(a, "overview: {s} or {d} generated reference file(s) are stale; run `selka overview {s} --write` and review the diff\n", .{ model.options.overview, outcome.stale, options.project });
    }
    try std.Io.File.stdout().writeStreamingAll(process.io, report.items);
    return if (current) 0 else 1;
}

/// Write the project page to `page`, and with `--data` the overview-v1 content beside it. The page's
/// data holds the document, the release note titles and the back link; `--data` holds only the document.
fn writePage(process: std.process.Init, a: std.mem.Allocator, model: *const loader.Model, document: overview_types.Document, options: Options, page: []const u8) !u8 {
    const releases = try notes.releaseNotes(a, process.io, model.root, model.options.changes, document.releases.history);
    const data = try std.json.Stringify.valueAlloc(a, .{ .overview = document, .release_notes = releases, .back = options.back }, .{});
    try std.Io.Dir.cwd().writeFile(process.io, .{ .sub_path = page, .data = try review_html.project(a, data) });
    if (options.data) |path| {
        const content = try std.json.Stringify.valueAlloc(a, document, .{});
        try std.Io.Dir.cwd().writeFile(process.io, .{ .sub_path = path, .data = try std.fmt.allocPrint(a, "{s}\n", .{content}) });
    }
    return 0;
}

fn parse(args: []const []const u8) ?Options {
    var project: ?[]const u8 = null;
    var mode: ?Mode = null;
    var options: Options = .{ .project = "", .mode = .check };
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, arg, "--write") or std.mem.eql(u8, arg, "--check")) {
            if (mode != null) return null;
            mode = if (std.mem.eql(u8, arg, "--write")) .write else .check;
        } else if (flagValue(args, &index, "--html")) |value| {
            if (mode != null or value.len == 0) return null;
            mode = .html;
            options.html = value;
        } else if (flagValue(args, &index, "--data")) |value| {
            if (options.data != null or value.len == 0) return null;
            options.data = value;
        } else if (flagValue(args, &index, "--back")) |value| {
            if (options.back != null) return null;
            options.back = value;
        } else if (std.mem.startsWith(u8, arg, "-") or project != null) {
            return null;
        } else {
            project = arg;
        }
    }
    options.project = project orelse return null;
    options.mode = mode orelse return null;
    if (options.mode == .html and options.json) return null;
    if (options.mode != .html and (options.data != null or options.back != null)) return null;
    return options;
}

/// The value of `flag` when the argument at `index` is that flag, which takes the next argument as its value.
fn flagValue(args: []const []const u8, index: *usize, flag: []const u8) ?[]const u8 {
    if (!std.mem.eql(u8, args[index.*], flag)) return null;
    if (index.* + 1 >= args.len) return null;
    index.* += 1;
    return args[index.*];
}

test "overview arguments take one mode: check, write or the project page" {
    try std.testing.expectEqual(Mode.check, parse(&.{ ".", "--check" }).?.mode);
    try std.testing.expectEqual(Mode.write, parse(&.{ ".", "--write", "--json" }).?.mode);
    const page = parse(&.{ ".", "--html", "p.html", "--data", "d.json", "--back", "../../index.html" }).?;
    try std.testing.expectEqual(Mode.html, page.mode);
    try std.testing.expectEqualStrings("p.html", page.html.?);
    try std.testing.expectEqualStrings("d.json", page.data.?);
    try std.testing.expectEqualStrings("../../index.html", page.back.?);
}

test "overview arguments refuse a page mixed with check, write or json, and the page options without it" {
    try std.testing.expect(parse(&.{ ".", "--html", "x.html", "--write" }) == null);
    try std.testing.expect(parse(&.{ ".", "--check", "--html", "x.html" }) == null);
    try std.testing.expect(parse(&.{ ".", "--html", "x.html", "--json" }) == null);
    try std.testing.expect(parse(&.{ ".", "--check", "--data", "d.json" }) == null);
    try std.testing.expect(parse(&.{ ".", "--html" }) == null);
    try std.testing.expect(parse(&.{ ".", "--html", "a.html", "--html", "b.html" }) == null);
    try std.testing.expect(parse(&.{"--check"}) == null);
}

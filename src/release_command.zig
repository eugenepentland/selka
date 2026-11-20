//! Native checked-release CLI: initialize, explain, verify and record public changes.
const std = @import("std");
const opts = @import("release_options.zig");
const loader = @import("release_project_load.zig");
const store = @import("overview_store.zig");
const reports = @import("release_report.zig");
const Context = @import("release_context.zig").Context;
const gate = @import("release_gate.zig");
const baseline = @import("api_diff_baseline.zig");
/// Run a release operation: 0 succeeds, 3 refuses a project, 2 is usage/host failure.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    var source: loader.Failure = .{};
    return command(process, args, &source) catch |err| {
        if (err == error.SourceError) {
            const options = opts.parse(args) catch return 2;
            return sourceFailure(process, options, err, &source) catch 2;
        }
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "selka release: {s}\n", .{@errorName(err)}) catch "selka release: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
}
fn command(process: std.process.Init, args: []const []const u8, source: *loader.Failure) !u8 {
    if (args.len == 0 or (args.len == 1 and std.mem.eql(u8, args[0], "--help"))) {
        try std.Io.File.stdout().writeStreamingAll(process.io, opts.usage);
        return if (args.len == 0) 2 else 0;
    }
    const options = opts.parse(args) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, opts.usage);
        return 2;
    };
    const a = process.arena.allocator();
    var model = loader.loadWith(process.gpa, process.io, options.project, source) catch |err| switch (err) {
        error.SourceError, error.IncompleteProject => return sourceFailure(process, options, err, source),
        else => return err,
    };
    defer model.deinit();
    try validateLayout(model);
    var report: reports.Report = .{ .allocator = a };
    defer report.deinit();
    const metadata = store.load(a, process.io, &model) catch |err| switch (err) {
        error.InvalidBaseline, error.InvalidHistory => {
            const path = if (err == error.InvalidBaseline) model.options.baseline else store.history_path;
            try std.Io.File.stderr().writeStreamingAll(process.io, try std.fmt.allocPrint(a, "selka release: malformed {s}: {s}\n", .{ path, @errorName(err) }));
            return 2;
        },
        else => return err,
    };
    var context: Context = .{ .process = process, .options = options, .model = &model, .metadata = metadata, .report = &report, .compiler = try std.process.executablePathAlloc(process.io, a) };
    return switch (options.action) {
        .check => blk: {
            const status = try gate.run(context);
            try report.render(process.io, options.json);
            break :blk status;
        },
        .init => try initialize(&context),
        .draft => try draft(context),
        .cut => try cut(context),
    };
}
fn sourceFailure(process: std.process.Init, options: opts.Options, err: anyerror, source: *const loader.Failure) !u8 {
    var report: reports.Report = .{ .allocator = process.arena.allocator() };
    const a = report.allocator;
    if (source.present and loader.isSynthesizedRoot(source.path)) {
        // The synthesized root names no project file: say a project module does not load.
        try report.atRule(source.code, .{ .path = options.project }, try std.fmt.allocPrint(a, "a project module does not load: {s}; repair the source before release checking", .{source.message}), source.rule);
    } else if (source.present) {
        // Name the file, position and compiler diagnostic instead of `SourceError`
        // (FR-413). The check step is the one that failed, exactly as if its own
        // check had printed this diagnostic.
        try report.atRule(source.code, .{ .path = source.path, .line = source.line, .column = source.column }, try std.fmt.allocPrint(a, "{s}; repair the source before release checking", .{source.message}), source.rule);
    } else try report.add("E_RELEASE_STEP_FAILED", options.project, 1, try std.fmt.allocPrint(a, "declaration loading failed: {s}; repair the source before release checking", .{@errorName(err)}));
    for (std.enums.values(opts.Step)) |step| {
        if (!options.steps.contains(step)) continue;
        try report.steps.append(report.allocator, .{
            .name = step,
            .status = if (step == .check) .failed else .skipped,
            .findings = if (step == .check) 1 else 0,
            .reason = if (step == .check) "" else "project declarations could not be loaded",
        });
    }
    try report.render(process.io, options.json);
    return 3;
}
fn refusal(context: Context, message: []const u8) !u8 {
    try std.Io.File.stderr().writeStreamingAll(context.process.io, try std.fmt.allocPrint(context.allocator(), "selka release: {s}\n", .{message}));
    return 3;
}
fn initialize(context: *Context) !u8 {
    if (context.options.adoption == .preview) return preview(context.*);
    if (context.metadata.previous != null or try context.exists(context.model.options.baseline)) return refusal(context.*, "baseline already exists; init never overwrites it");
    if (context.options.adoption != .none) try printAdoptions(context.*, try adopt(context));
    const a = context.allocator();
    const bytes = try @import("api_diff.zig").snapshotPublic(a, context.model.index, context.model.modules);
    try std.Io.Dir.cwd().createDirPath(context.process.io, try context.path(try std.fs.path.join(a, &.{ context.model.options.decisions, "unreleased" })));
    if (!try context.exists(store.history_path)) try context.write(store.history_path, "", true);
    try context.write(context.model.options.baseline, bytes, true);
    try writeOverview(context.*);
    try std.Io.File.stdout().writeStreamingAll(context.process.io, "release init: initialized baseline, decisions, history and overview\n");
    return 0;
}
/// Print every comment block `--adopt-comments` will adopt, or adopted.
fn printAdoptions(context: Context, adoptions: []const @import("release_adopt.zig").Adoption) !void {
    if (adoptions.len == 0) {
        try std.Io.File.stdout().writeStreamingAll(context.process.io, "adopt-comments: no adjacent comment blocks to adopt\n");
        return;
    }
    for (adoptions) |item| {
        const line = try std.fmt.allocPrint(context.allocator(), "adopt-comments: {s}:{d}: {s}\n", .{ item.path, item.line, item.target });
        try std.Io.File.stdout().writeStreamingAll(context.process.io, line);
    }
}

/// List the adoptions without writing a source, baseline or overview file.
fn preview(context: Context) !u8 {
    const a = context.allocator();
    var adoptions: std.ArrayList(@import("release_adopt.zig").Adoption) = .empty;
    for (context.model.modules) |id| {
        const module = context.model.project.modules.items[id];
        const report = try @import("release_adopt.zig").rewriteReport(a, module, context.model.index.units[id]);
        try adoptions.appendSlice(a, report.adoptions);
    }
    try printAdoptions(context, adoptions.items);
    return 0;
}

fn adopt(context: *Context) ![]const @import("release_adopt.zig").Adoption {
    const a = context.allocator();
    const previous = try baseline.parseReleaseBaseline(a, try @import("api_diff.zig").snapshotPublic(a, context.model.index, context.model.modules));
    var originals: std.ArrayList(Original) = .empty;
    var adoptions: std.ArrayList(@import("release_adopt.zig").Adoption) = .empty;
    var successful = false;
    defer if (!successful) restore(context.*, originals.items);
    for (context.model.modules) |id| {
        const module = context.model.project.modules.items[id];
        const report = try @import("release_adopt.zig").rewriteReport(a, module, context.model.index.units[id]);
        if (std.mem.eql(u8, module.src.bytes, report.source)) continue;
        try adoptions.appendSlice(a, report.adoptions);
        try originals.append(a, .{ .path = try a.dupe(u8, module.src.path), .bytes = try a.dupe(u8, module.src.bytes) });
        try context.write(module.src.path, report.source, false);
    }
    var updated = try loader.load(context.process.gpa, context.process.io, context.options.project);
    errdefer updated.deinit();
    const current = try baseline.parseReleaseBaseline(a, try @import("api_diff.zig").snapshotPublic(a, updated.index, updated.modules));
    try @import("release_adopt.zig").confirmInterface(a, previous, current);
    context.model.deinit();
    context.model.* = updated;
    successful = true;
    return adoptions.items;
}
const Original = struct { path: []const u8, bytes: []const u8 };
fn draft(context: Context) !u8 {
    if (context.metadata.previous == null) return refusal(context, "release baseline is missing; run selka release init PROJECT");
    const a = context.allocator();
    const path = try std.fs.path.join(a, &.{ context.model.options.decisions, "unreleased", try std.mem.concat(a, u8, &.{ context.options.name.?, ".md" }) });
    if (try context.exists(path)) return refusal(context, "decision already exists; draft never overwrites it");
    const current = try baseline.parseReleaseBaseline(a, try @import("api_diff.zig").snapshotPublic(a, context.model.index, context.model.modules));
    const issues = try @import("release_decisions.zig").coverageAt(a, context.metadata.previous, current, context.metadata.decisions, .{});
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, "# TODO: decision title\n\n");
    if (context.options.date) |date| try text.print(a, "Date: {s}\n", .{date});
    try text.appendSlice(a, "Changes: ");
    var count: usize = 0;
    for (issues) |issue| {
        if (!std.mem.eql(u8, issue.code, "E_RELEASE_DECISION_MISSING")) continue;
        if (count != 0) try text.appendSlice(a, ", ");
        try text.appendSlice(a, issue.name.?);
        count += 1;
    }
    try text.appendSlice(a, "\nWhy: TODO\n");
    try context.write(path, text.items, true);
    try std.Io.File.stdout().writeStreamingAll(context.process.io, try std.fmt.allocPrint(a, "release draft: wrote {s}; replace the title and Why placeholders\n", .{path}));
    return 0;
}
fn cut(context: Context) !u8 {
    const name = context.options.name.?;
    if (std.mem.eql(u8, name, "unreleased")) return refusal(context, "unreleased is the reserved pending decision directory");
    const a = context.allocator();
    const destination = try std.fs.path.join(a, &.{ context.model.options.decisions, name });
    if (try context.exists(destination)) return refusal(context, "release name already exists");
    for (context.metadata.history) |entry| if (std.mem.eql(u8, entry.name, name)) return refusal(context, "release name already exists in history");
    const changes_pending = try std.fs.path.join(a, &.{ context.model.options.changes, "unreleased" });
    const changes_destination = try std.fs.path.join(a, &.{ context.model.options.changes, name });
    const moving_notes = try context.exists(changes_pending);
    if (moving_notes) {
        if (try context.exists(changes_destination)) return refusal(context, "change notes already exist under this release name; cut never overwrites them");
    }
    const status = try gate.run(context);
    try context.report.render(context.process.io, false);
    if (status != 0) return status;
    const pending = try std.fs.path.join(a, &.{ context.model.options.decisions, "unreleased" });
    const bytes = try @import("api_diff.zig").snapshotPublic(a, context.model.index, context.model.modules);
    const has_changes = try context.exists(context.model.options.changes);
    const notes = if (moving_notes) try countNotes(context, changes_pending) else 0;
    var history: std.ArrayList(u8) = .empty;
    for (context.metadata.history) |entry| try appendHistory(a, &history, entry.name, entry.decisions, entry.notes, has_changes);
    var count: usize = 0;
    for (context.metadata.decisions) |decision| count += @intFromBool(decision.pending);
    try appendHistory(a, &history, name, count, notes, has_changes);
    // All refusal conditions have passed before the first write. Overview is last.
    try context.write(context.model.options.baseline, bytes, false);
    if (try context.exists(pending)) {
        try std.Io.Dir.cwd().rename(try context.path(pending), std.Io.Dir.cwd(), try context.path(destination), context.process.io);
    } else try std.Io.Dir.cwd().createDirPath(context.process.io, try context.path(destination));
    try std.Io.Dir.cwd().createDirPath(context.process.io, try context.path(pending));
    if (moving_notes) {
        try std.Io.Dir.cwd().rename(try context.path(changes_pending), std.Io.Dir.cwd(), try context.path(changes_destination), context.process.io);
        try std.Io.Dir.cwd().createDirPath(context.process.io, try context.path(changes_pending));
    }
    try context.write(store.history_path, history.items, false);
    try writeOverview(context);
    const line = if (notes == 0)
        try std.fmt.allocPrint(a, "release cut: {s} ({d} decisions)\n", .{ name, count })
    else
        try std.fmt.allocPrint(a, "release cut: {s} ({d} decisions, {d} change notes)\n", .{ name, count, notes });
    try std.Io.File.stdout().writeStreamingAll(context.process.io, line);
    return 0;
}

/// Append one history row. The notes column is written when the project has a
/// changes directory or the row already records notes, so older rows stay as they were.
fn appendHistory(a: std.mem.Allocator, history: *std.ArrayList(u8), name: []const u8, decisions_count: usize, notes_count: usize, has_changes: bool) !void {
    if (has_changes or notes_count != 0) {
        try history.print(a, "{s}\t{d}\t{d}\n", .{ name, decisions_count, notes_count });
        return;
    }
    try history.print(a, "{s}\t{d}\n", .{ name, decisions_count });
}

/// Count the Markdown change notes under a project-relative directory, at any depth.
fn countNotes(context: Context, relative: []const u8) !usize {
    const io = context.process.io;
    var directory = std.Io.Dir.cwd().openDir(io, try context.path(relative), .{ .iterate = true }) catch return error.HostIo;
    defer directory.close(io);
    var walker = try directory.walk(context.allocator());
    defer walker.deinit();
    var count: usize = 0;
    while (walker.next(io) catch return error.HostIo) |item| {
        if (item.kind == .file and std.mem.endsWith(u8, item.path, ".md")) count += 1;
    }
    return count;
}
fn writeOverview(context: Context) !void {
    const a = context.allocator();
    const metadata = try store.load(a, context.process.io, context.model);
    const rendered = try @import("overview.zig").render(a, context.model, metadata);
    try @import("overview.zig").writeRendered(a, context.process.io, context.model, rendered);
}

fn validateLayout(model: loader.Model) !void {
    const files = [_][]const u8{ model.options.baseline, model.options.overview, store.history_path, model.options.changes };
    for (files, 0..) |path, i| {
        if (inside(model.options.decisions, path)) return error.InvalidReleasePaths;
        for (files[i + 1 ..]) |other| if (inside(path, other) or inside(other, path)) return error.InvalidReleasePaths;
        if (std.mem.startsWith(u8, path, model.options.decisions)) {
            const suffix = path[model.options.decisions.len..];
            if (std.mem.eql(u8, suffix, "/unreleased") or std.mem.startsWith(u8, suffix, "/unreleased/")) return error.InvalidReleasePaths;
        }
        for (model.project.modules.items) |module| if (std.mem.eql(u8, path, module.src.path)) return error.InvalidReleasePaths;
    }
}
fn inside(path: []const u8, directory: []const u8) bool {
    return std.mem.eql(u8, path, directory) or (path.len > directory.len and std.mem.startsWith(u8, path, directory) and path[directory.len] == '/');
}

fn restore(context: Context, originals: []const Original) void {
    for (originals) |original| context.write(original.path, original.bytes, false) catch |err| {
        const message = std.fmt.allocPrint(context.allocator(), "selka release: restoring {s} failed: {s}\n", .{ original.path, @errorName(err) }) catch return;
        std.Io.File.stderr().writeStreamingAll(context.process.io, message) catch return;
    };
}

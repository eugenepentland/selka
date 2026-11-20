//! Ordered release checks with explicit subset and failed-dependency reporting.
const std = @import("std");
const product = @import("product.zig");
const Context = @import("release_context.zig").Context;
const reports = @import("release_report.zig");
const options = @import("release_options.zig");
const sources = @import("release_gate_sources.zig");
const decisions = @import("release_decisions.zig");
const baseline = @import("api_diff_baseline.zig");
const store = @import("overview_store.zig");
/// Native gate, metadata, documentation and declaration failures.
pub const Error = sources.Error || @import("release_references.zig").Error || store.Error || @import("overview.zig").Error || @import("lint_config.zig").Error || @import("review_side.zig").Error;
/// Run the selected ordered steps, retaining findings in the caller's report.
pub fn run(context: Context) Error!u8 {
    var check_failed = false;
    for (std.enums.values(options.Step)) |step| {
        if (!context.options.steps.contains(step)) continue;
        var result: reports.Result = .{ .name = step };
        const start = context.report.findings.items.len;
        if (check_failed and (step == .lint or step == .tests)) {
            result.status = .skipped;
            result.reason = "check failed";
        } else switch (step) {
            .format => try sources.format(context),
            .check => try sources.check(context),
            .lint => try sources.lint(context),
            .tests => result.detail = try sources.tests(context),
            .docs => try docs(context),
            .decisions => try coverage(context),
            .overview => try overview(context),
        }
        result.findings = context.report.errors(start);
        if (result.findings != 0) result.status = .failed;
        if (step == .check and result.status == .failed) check_failed = true;
        try context.report.steps.append(context.allocator(), result);
    }
    return context.report.status();
}
fn docs(context: Context) !void {
    const a = context.allocator();
    var min_chars: usize = 12;
    if (try store.readOptional(a, context.process.io, context.model.root, product.project_file)) |bytes| {
        var failure: @import("lint_config.zig").Failure = .{};
        var config = try @import("lint_config.zig").parseConfig(a, bytes, &failure);
        defer config.deinit(a);
        min_chars = config.min_chars orelse 12;
    }
    var findings: std.ArrayList(@import("lint.zig").Finding) = .empty;
    try @import("lint.zig").appendProjectDocumentation(a, context.model.index, context.model.modules, min_chars, &findings);
    for (findings.items) |finding| {
        const id = context.model.project.names.get(finding.subject.module) orelse return error.IncompleteProject;
        const src = context.model.project.modules.items[id].src;
        const bytes = try @import("diagnostic_output.zig").render(a, .{ .code = finding.code, .severity = .err, .span = finding.span, .message = finding.message }, src, .json);
        _ = try context.report.appendJson(bytes, false);
    }
    try @import("release_references.zig").check(context);
    for (try @import("release_context.zig").files(context, .markdown)) |path| {
        const child = try context.child(&.{ "doctest", ".", "--filter", path, "--release-docs" });
        try child.checkHost();
        if (child.status != 0) try context.report.add("E_RELEASE_STEP_FAILED", path, 1, try std.fmt.allocPrint(a, "Markdown examples refused: {s}{s}", .{ child.stdout, child.stderr }));
    }
}
/// Validate all pending decisions and the current public delta, including removals,
/// and every pending change note, so `release cut` never files an invalid note.
pub fn coverage(context: Context) Error!void {
    const a = context.allocator();
    const current = try baseline.parseReleaseBaseline(a, try @import("api_diff.zig").snapshotPublic(a, context.model.index, context.model.modules));
    for (context.metadata.issues) |issue| try appendIssue(context, issue);
    try pendingNotes(context);
    const pending = try std.fs.path.join(a, &.{ context.model.options.decisions, "unreleased" });
    const issues = try decisions.coverageAt(a, context.metadata.previous, current, context.metadata.decisions, .{ .baseline = context.model.options.baseline, .pending = pending });
    for (issues) |issue| try appendIssue(context, issue);
    // Missing-baseline coverage returns early; pending Changes must still resolve.
    if (context.metadata.previous == null) {
        for (context.metadata.decisions) |decision| {
            if (!decision.pending) continue;
            for (decision.changes) |name| {
                var found = false;
                for (current) |entry| if (std.mem.eql(u8, entry.display, name)) {
                    found = true;
                    break;
                };
                if (!found) try context.report.add("E_RELEASE_REFERENCE_UNKNOWN", decision.path, 1, try std.fmt.allocPrint(a, "Changes names no current public declaration: {s}", .{name}));
            }
        }
    }
}
/// Report each problem of a pending change note under `changes/unreleased`, as the
/// change review reports the notes of a change.
fn pendingNotes(context: Context) !void {
    const a = context.allocator();
    const pending = try std.fs.path.join(a, &.{ context.model.options.changes, "unreleased" });
    const files = try @import("review_side.zig").markdownUnder(a, context.process.io, context.model.root, pending);
    for (try noteIssues(a, files)) |issue| try context.report.add(issue.code, issue.path, issue.line, issue.message);
}

/// Every problem of the given change notes, in the order the files give them.
fn noteIssues(a: std.mem.Allocator, files: []const @import("review_side.zig").File) ![]const decisions.Issue {
    var issues: std.ArrayList(decisions.Issue) = .empty;
    for (files) |file| {
        const parsed = try @import("change_notes.zig").parse(a, file.path, file.bytes);
        try issues.appendSlice(a, parsed.issues);
    }
    return issues.items;
}

test "release gate reports every problem of a pending change note" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]@import("review_side.zig").File{
        .{ .path = "changes/unreleased/bad.md", .bytes = "# Bad\n\nSummary: TODO\n" },
        .{ .path = "changes/unreleased/good.md", .bytes = "# Good\n\nSummary: " ++ "Serve connections on one event loop with a bounded table and an idle timeout." ++ "\n" },
    };
    const issues = try noteIssues(a, &files);
    try std.testing.expectEqual(@as(usize, 2), issues.len);
    try std.testing.expectEqualStrings("E_REVIEW_NOTE_INVALID", issues[0].code);
    try std.testing.expectEqualStrings("changes/unreleased/bad.md", issues[0].path);
    try std.testing.expectEqual(@as(usize, 3), issues[0].line);
}
fn appendIssue(context: Context, issue: decisions.Issue) !void {
    const a = context.allocator();
    const message = if (std.mem.eql(u8, issue.code, "E_RELEASE_NO_BASELINE"))
        try std.fmt.allocPrint(a, "release baseline is missing; run `selka release init {s}`", .{context.options.project})
    else if (std.mem.eql(u8, issue.code, "E_RELEASE_DECISION_MISSING"))
        try std.fmt.allocPrint(a, "{s} changed its public interface without a pending decision; run `selka release draft {s} --name SLUG`", .{ issue.name orelse "declaration", context.options.project })
    else if (issue.name) |name| try std.fmt.allocPrint(a, "{s}: {s}", .{ name, issue.message }) else issue.message;
    try context.report.add(issue.code, issue.path, issue.line, message);
}
fn overview(context: Context) !void {
    const a = context.allocator();
    const rendered = try @import("overview.zig").render(a, context.model, context.metadata);
    const outcome = try @import("overview.zig").compare(a, context.process.io, context.model, rendered);
    if (!outcome.current) {
        const message = try std.fmt.allocPrint(a, "the overview or one of its generated references does not match the project " ++
            "({d} stale generated file(s)); run `selka overview {s} --write` and review the diff\n{s}", .{ outcome.stale, context.options.project, outcome.diff });
        try context.report.add("E_RELEASE_OVERVIEW_STALE", context.model.options.overview, 1, message);
    }
    const api_files = try @import("release_context.zig").files(context, .api);
    if (api_files.len == 0) return;
    for (context.model.modules) |id| {
        const module = context.model.project.modules.items[id];
        const path = try @import("interface_files.zig").apiPath(a, module.src.path);
        const expected = try @import("interface_files.zig").render(a, context.model.index, id);
        const old = try store.readOptional(a, context.process.io, context.model.root, path);
        if (old == null or !std.mem.eql(u8, old.?, expected)) try staleApi(context, path, module.src.path);
    }
    for (api_files) |path| {
        const source_path = try std.mem.concat(a, u8, &.{ path[0 .. path.len - @import("interface_files.zig").extension.len], product.source_suffix });
        if (try context.exists(source_path)) {
            for (context.model.project.modules.items, 0..) |module, id| {
                if (!std.mem.eql(u8, source_path, module.src.path)) continue;
                const expected = try @import("interface_files.zig").render(a, context.model.index, id);
                const old = (try store.readOptional(a, context.process.io, context.model.root, path)) orelse continue;
                if (!std.mem.eql(u8, old, expected)) try staleApi(context, path, source_path);
                break;
            }
            continue;
        }
        const bytes = (try store.readOptional(a, context.process.io, context.model.root, path)) orelse continue;
        if (@import("interface_files.zig").generated(bytes)) try staleApi(context, path, context.model.selection.entries[0]);
    }
}
fn staleApi(context: Context, path: []const u8, root: []const u8) !void {
    try context.report.add("E_INTERFACE_FILE_STALE", path, 1, try std.fmt.allocPrint(context.allocator(), "interface file is missing, stale or orphaned; run `selka api {s} --write` and review its diff", .{root}));
}

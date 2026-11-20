//! The two renderings of a review: the terminal summary `selka review` prints, and
//! the `review-v1` object `--json` writes. Both are pure over the review's values.
const std = @import("std");
const core = @import("review_core.zig");
const review_git = @import("review_git.zig");
const review_tests = @import("review_tests.zig");
const review_files = @import("review_files.zig");
const review_inside = @import("review_inside.zig");
const review_attention = @import("review_attention.zig");

/// Allocation is the only failure: the renderings are built in memory.
pub const Error = std.mem.Allocator.Error;

/// Refusals printed in full before the rest are counted.
const max_refusals = 60;
/// The most lines a passing review prints, the summary line included.
const max_passing_lines = 30;
/// The most lines the attention block prints, its `! ` entries and their items together.
const max_attention_lines = 15;
/// Items each attention entry prints before counting the rest.
const max_attention_items = 5;
/// Functions the terminal names, one line each, before the rest are counted.
const max_inside_lines = 10;
/// The JSON format name every `--json` object carries.
const json_version = "review-v1";

/// The counts the summary line and the last line report.
const Counts = struct { added: usize = 0, changed: usize = 0, removed: usize = 0, explained: usize = 0 };

/// The terminal summary: the verdict, the counts, the tests when `--test` ran, the
/// attention list, the refusals, the interface when the review passes, and a last
/// `review:` line with the totals. A passing review prints at most `max_passing_lines`.
/// The caller owns the exact-size result; intermediate rendering storage is released.
pub fn text(a: std.mem.Allocator, review: core.Review) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    const counts = countsOf(review);
    const verdict = if (review.refusals.len == 0) "OK" else "REFUSED";
    try out.print(scratch, "review: {s} {s}..{s}: {s}\n", .{ review.project, review_git.shortName(review.range.base), headLabel(review.range), verdict });
    try out.print(scratch, "{d} public changes ({d} added, {d} changed, {d} removed), {d} explained by a decision; {d} decisions and {d} change notes in the change\n", .{
        review.interface.len, counts.added, counts.changed, counts.removed, counts.explained, review.evidence.decisions.len, review.evidence.notes.len,
    });
    var lines: usize = 2;
    if (review.facts.tests_run) |run| {
        try testsLine(scratch, &out, run);
        lines += 1;
    }
    lines += try attentionLines(scratch, &out, review.facts.attention, max_attention_lines);
    lines += try insideLines(scratch, &out, review.facts.inside);
    const printed = @min(max_refusals, review.refusals.len);
    for (review.refusals[0..printed]) |refusal| try refusalLine(scratch, &out, refusal);
    if (review.refusals.len > printed) try out.print(scratch, "… {d} more\n", .{review.refusals.len - printed});
    if (review.refusals.len == 0) {
        // The final summary line is one of the passing review's lines.
        try interfaceLines(scratch, &out, review.interface, max_passing_lines - lines - 1);
        try out.print(scratch, "review: passes; {d} public changes, {d} change notes, {d} decisions\n", .{ review.interface.len, review.evidence.notes.len, review.evidence.decisions.len });
    } else {
        try out.print(scratch, "review: refused; {d} refusals; {d} public changes, {d} change notes, {d} decisions\n", .{ review.refusals.len, review.interface.len, review.evidence.notes.len, review.evidence.decisions.len });
    }
    return a.dupe(u8, out.items);
}

/// The verdict counts of the `--test` run, or that it printed no summary line.
fn testsLine(a: std.mem.Allocator, out: *std.ArrayList(u8), run: review_tests.Run) Error!void {
    if (!run.found) {
        try out.print(a, "tests at the head: the run printed no summary line\n", .{});
        return;
    }
    try out.print(a, "tests at the head: {d} passed, {d} cached, {d} failed, {d} skipped\n", .{ run.passed, run.cached, run.failed, run.skipped });
}

/// Print the attention entries, each as a `! text` line and up to `max_attention_items`
/// indented items, within `budget` lines. An entry whose items are listed below the list
/// (`listed_below`) prints its text alone. An entry that does not fit is counted in one
/// `! … N more` line. Returns the number of lines printed.
fn attentionLines(a: std.mem.Allocator, out: *std.ArrayList(u8), entries: []const core.Attention, budget: usize) Error!usize {
    var printed: usize = 0;
    for (entries, 0..) |entry, index| {
        const items: []const []const u8 = if (entry.listed_below) &.{} else entry.items;
        const shown = @min(items.len, max_attention_items);
        const needed = 1 + shown + @intFromBool(items.len > shown);
        const reserved = @intFromBool(index + 1 < entries.len);
        if (printed + needed + reserved > budget) {
            try out.print(a, "! … {d} more\n", .{entries.len - index});
            return printed + 1;
        }
        try out.print(a, "! {s}\n", .{entry.text});
        for (items[0..shown]) |item| try out.print(a, "  {s}\n", .{item});
        if (items.len > shown) try out.print(a, "  … {d} more\n", .{items.len - shown});
        printed += needed;
    }
    return printed;
}

/// The terminal lines of the functions the change edits: one `name: state, lines A → B,
/// decision points C → D` line each, at most `max_inside_lines` and then a count of the rest.
/// The helpers of test modules share one line. Returns the number of lines printed.
fn insideLines(a: std.mem.Allocator, out: *std.ArrayList(u8), functions: []const review_inside.Function) Error!usize {
    var printed: usize = 0;
    var others: usize = 0;
    var helpers: std.ArrayList([]const u8) = .empty;
    for (functions) |function| {
        if (review_inside.isTestFile(function.location.file)) {
            try helpers.append(a, function.name);
            continue;
        }
        others += 1;
        if (others > max_inside_lines) continue;
        const measure = function.measure;
        try out.print(a, "  {s}: {s}, lines {d} → {d}, decision points {d} → {d}\n", .{
            function.name, stateWord(function.state), measure.lines.before, measure.lines.after, measure.decision_points.before, measure.decision_points.after,
        });
        printed += 1;
    }
    if (others > max_inside_lines) {
        try out.print(a, "  … {d} more\n", .{others - max_inside_lines});
        printed += 1;
    }
    if (helpers.items.len != 0) {
        try out.print(a, "  test helpers changed: {s}\n", .{try std.mem.join(a, ", ", helpers.items)});
        printed += 1;
    }
    return printed;
}

/// The word the terminal gives a function's state.
fn stateWord(state: review_inside.State) []const u8 {
    return switch (state) {
        .changed => "edited",
        .added => "added",
        .removed => "removed",
    };
}

/// One refusal as `path:line: error[CODE]: message`, or without the location it does not have.
fn refusalLine(a: std.mem.Allocator, out: *std.ArrayList(u8), refusal: core.Refusal) Error!void {
    if (refusal.path) |path| {
        if (refusal.line) |line| {
            try out.print(a, "{s}:{d}: error[{s}]: {s}\n", .{ path, line, refusal.code, refusal.message });
        } else {
            try out.print(a, "{s}: error[{s}]: {s}\n", .{ path, refusal.code, refusal.message });
        }
    } else try out.print(a, "error[{s}]: {s}\n", .{ refusal.code, refusal.message });
    if (refusal.source_code) |code| try out.print(a, "  note: source diagnostic {s}\n", .{code});
    if (refusal.rule) |rule| try out.print(a, "  note: ownership rule {s}\n", .{@tagName(rule)});
}

/// One line per interface item: its name and its sentences, within `room` lines. When the
/// items do not all fit, the last line counts the rest.
fn interfaceLines(a: std.mem.Allocator, out: *std.ArrayList(u8), interface: []const core.Item, room: usize) Error!void {
    if (room == 0) return;
    const shown = if (interface.len > room) room - 1 else interface.len;
    for (interface[0..shown]) |item| {
        const joined = try std.mem.join(a, "; ", item.sentences);
        try out.print(a, "  {s}: {s}\n", .{ item.name, joined });
    }
    if (interface.len > shown) try out.print(a, "  … {d} more\n", .{interface.len - shown});
}

/// The change counts: added, changed and removed declarations, and those a decision explains.
fn countsOf(review: core.Review) Counts {
    var counts: Counts = .{};
    for (review.interface) |item| {
        switch (item.change) {
            .added => counts.added += 1,
            .changed => counts.changed += 1,
            .removed => counts.removed += 1,
        }
        if (item.decision != null) counts.explained += 1;
    }
    return counts;
}

/// The head as the first line names it: the working tree, or the abbreviated commit.
fn headLabel(range: core.Range) []const u8 {
    if (range.working_tree) return "working tree";
    return review_git.shortName(range.head);
}

/// The `review-v1` object: version, project, range, verdict, notes, decisions, interface,
/// body-only names, the source flag, the behaviour, the functions the change edits (`inside`),
/// the generated and cited files, the `--test` counts when they ran, and the attention list.
/// Optional fields that are absent are left out.
pub fn json(a: std.mem.Allocator, review: core.Review) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    writeReview(&out.writer, review) catch return error.OutOfMemory;
    out.writer.writeAll("\n") catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn writeReview(writer: *std.Io.Writer, review: core.Review) std.json.Stringify.Error!void {
    var json_out: std.json.Stringify = .{ .writer = writer };
    try json_out.beginObject();
    try field(&json_out, "version");
    try json_out.write(json_version);
    try field(&json_out, "project");
    try json_out.write(review.project);
    try field(&json_out, "range");
    try json_out.beginObject();
    try field(&json_out, "base");
    try json_out.write(review.range.base);
    try field(&json_out, "head");
    try json_out.write(review.range.head);
    try field(&json_out, "working_tree");
    try json_out.write(review.range.working_tree);
    try json_out.endObject();
    try field(&json_out, "verdict");
    try json_out.beginObject();
    try field(&json_out, "ok");
    try json_out.write(review.refusals.len == 0);
    try field(&json_out, "refusals");
    try json_out.beginArray();
    for (review.refusals) |refusal| try writeRefusal(&json_out, refusal);
    try json_out.endArray();
    try json_out.endObject();
    try field(&json_out, "notes");
    try json_out.beginArray();
    for (review.evidence.notes) |note| try writeNote(&json_out, note);
    try json_out.endArray();
    try field(&json_out, "decisions");
    try json_out.beginArray();
    for (review.evidence.decisions) |decision| try writeDecision(&json_out, decision);
    try json_out.endArray();
    try field(&json_out, "interface");
    try json_out.beginArray();
    for (review.interface) |item| try writeItem(&json_out, item);
    try json_out.endArray();
    try field(&json_out, "body_changed");
    try json_out.write(review.facts.body_changed);
    try field(&json_out, "source_changed");
    try json_out.write(review.facts.source_changed);
    try field(&json_out, "behaviour");
    try writeBehaviour(&json_out, review.facts.behaviour);
    try field(&json_out, "inside");
    try writeInside(&json_out, review.facts.inside);
    try field(&json_out, "generated");
    try json_out.beginArray();
    for (review.facts.files.generated) |generated| try writeGenerated(&json_out, generated);
    try json_out.endArray();
    try field(&json_out, "citations");
    try writeCitations(&json_out, review.facts.files.citations);
    if (review.facts.tests_run) |run| {
        try field(&json_out, "tests_run");
        try writeRun(&json_out, run);
    }
    try field(&json_out, "attention");
    try json_out.beginArray();
    for (review.facts.attention) |entry| try writeAttention(&json_out, entry);
    try json_out.endArray();
    try json_out.endObject();
}

fn field(json_out: *std.json.Stringify, name: []const u8) std.json.Stringify.Error!void {
    try json_out.objectField(name);
}

fn writeRefusal(json_out: *std.json.Stringify, refusal: core.Refusal) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "code");
    try json_out.write(refusal.code);
    try field(json_out, "message");
    try json_out.write(refusal.message);
    if (refusal.name) |name| {
        try field(json_out, "name");
        try json_out.write(name);
    }
    if (refusal.path) |path| {
        try field(json_out, "path");
        try json_out.write(path);
    }
    if (refusal.line) |line| {
        try field(json_out, "line");
        try json_out.write(line);
    }
    if (refusal.source_code) |code| {
        try field(json_out, "source_code");
        try json_out.write(code);
    }
    if (refusal.rule) |rule| {
        try field(json_out, "rule");
        try json_out.write(@tagName(rule));
    }
    try json_out.endObject();
}

fn writeNote(json_out: *std.json.Stringify, note: core.Note) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "path");
    try json_out.write(note.path);
    try field(json_out, "title");
    try json_out.write(note.title);
    try field(json_out, "summary");
    try json_out.write(note.summary);
    try field(json_out, "valid");
    try json_out.write(note.valid);
    try json_out.endObject();
}

fn writeDecision(json_out: *std.json.Stringify, decision: core.Decision) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "path");
    try json_out.write(decision.path);
    try field(json_out, "title");
    try json_out.write(decision.title);
    try field(json_out, "changes");
    try json_out.write(decision.changes);
    try field(json_out, "valid");
    try json_out.write(decision.valid);
    try field(json_out, "why");
    try json_out.write(decision.why);
    try field(json_out, "rejected");
    try json_out.write(decision.rejected);
    try json_out.endObject();
}

fn writeItem(json_out: *std.json.Stringify, item: core.Item) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "name");
    try json_out.write(item.name);
    try field(json_out, "module");
    try json_out.write(item.module);
    try field(json_out, "kind");
    try json_out.write(item.kind);
    try field(json_out, "change");
    try json_out.write(@tagName(item.change));
    try field(json_out, "sentences");
    try json_out.write(item.sentences);
    try field(json_out, "signature");
    try json_out.write(item.signatures.signature);
    if (item.signatures.old_signature) |old| {
        try field(json_out, "old_signature");
        try json_out.write(old);
    }
    if (item.signatures.gained_authority.len != 0) {
        try field(json_out, "gained_authority");
        try json_out.write(item.signatures.gained_authority);
    }
    if (item.decision) |title| {
        try field(json_out, "decision");
        try json_out.write(title);
    }
    try json_out.endObject();
}

/// The behaviour object: the docstring examples whose output changed, and the tests added,
/// changed and removed, each with its module and name.
fn writeBehaviour(json_out: *std.json.Stringify, behaviour: core.Behaviour) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "examples_changed");
    try json_out.beginArray();
    for (behaviour.examples_changed) |change| {
        try json_out.beginObject();
        try field(json_out, "name");
        try json_out.write(change.name);
        try field(json_out, "source");
        try json_out.write(change.source);
        try field(json_out, "old");
        try json_out.write(change.old);
        try field(json_out, "new");
        try json_out.write(change.new);
        try json_out.endObject();
    }
    try json_out.endArray();
    try field(json_out, "tests_added");
    try writeRefs(json_out, behaviour.tests_added);
    try field(json_out, "tests_changed");
    try json_out.beginArray();
    for (behaviour.tests_changed) |changed| {
        try json_out.beginObject();
        try field(json_out, "module");
        try json_out.write(changed.module);
        try field(json_out, "name");
        try json_out.write(changed.name);
        try field(json_out, "diff");
        try json_out.write(changed.diff);
        try json_out.endObject();
    }
    try json_out.endArray();
    try field(json_out, "tests_removed");
    try writeRefs(json_out, behaviour.tests_removed);
    try json_out.endObject();
}

fn writeRefs(json_out: *std.json.Stringify, refs: []const review_tests.Ref) std.json.Stringify.Error!void {
    try json_out.beginArray();
    for (refs) |ref| {
        try json_out.beginObject();
        try field(json_out, "module");
        try json_out.write(ref.module);
        try field(json_out, "name");
        try json_out.write(ref.name);
        try json_out.endObject();
    }
    try json_out.endArray();
}

fn writeGenerated(json_out: *std.json.Stringify, generated: review_files.Generated) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "path");
    try json_out.write(generated.path);
    try field(json_out, "first_line");
    try json_out.write(generated.first_line);
    try field(json_out, "lines_before");
    try json_out.write(generated.lines_before);
    try field(json_out, "lines_after");
    try json_out.write(generated.lines_after);
    try json_out.endObject();
}

/// The functions the change edits: name, visibility, state, file, line, the code lines and
/// decision points before and after, the signals, and the bounded diff.
fn writeInside(json_out: *std.json.Stringify, functions: []const review_inside.Function) std.json.Stringify.Error!void {
    try json_out.beginArray();
    for (functions) |function| {
        try json_out.beginObject();
        try field(json_out, "name");
        try json_out.write(function.name);
        try field(json_out, "public");
        try json_out.write(function.public);
        try field(json_out, "state");
        try json_out.write(@tagName(function.state));
        try field(json_out, "file");
        try json_out.write(function.location.file);
        try field(json_out, "line");
        try json_out.write(function.location.line);
        try field(json_out, "lines");
        try writePair(json_out, function.measure.lines);
        try field(json_out, "decision_points");
        try writePair(json_out, function.measure.decision_points);
        try field(json_out, "signals");
        try json_out.beginArray();
        for (function.signals) |signal| {
            try json_out.beginObject();
            try field(json_out, "kind");
            try json_out.write(signal.kind.label());
            try field(json_out, "text");
            try json_out.write(signal.text);
            try json_out.endObject();
        }
        try json_out.endArray();
        try field(json_out, "diff");
        try json_out.write(function.diff);
        try json_out.endObject();
    }
    try json_out.endArray();
}

/// A before and after count as the two-element array `[before, after]`.
fn writePair(json_out: *std.json.Stringify, pair: review_inside.Pair) std.json.Stringify.Error!void {
    try json_out.beginArray();
    try json_out.write(pair.before);
    try json_out.write(pair.after);
    try json_out.endArray();
}

/// The citations object: the issue ids the comment lines add and remove, each with its file.
fn writeCitations(json_out: *std.json.Stringify, citations: review_files.Citations) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "added");
    try writeCitationList(json_out, citations.added);
    try field(json_out, "removed");
    try writeCitationList(json_out, citations.removed);
    try json_out.endObject();
}

fn writeCitationList(json_out: *std.json.Stringify, list: []const review_files.Citation) std.json.Stringify.Error!void {
    try json_out.beginArray();
    for (list) |citation| {
        try json_out.beginObject();
        try field(json_out, "id");
        try json_out.write(citation.id);
        try field(json_out, "path");
        try json_out.write(citation.path);
        try json_out.endObject();
    }
    try json_out.endArray();
}

fn writeRun(json_out: *std.json.Stringify, run: review_tests.Run) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "passed");
    try json_out.write(run.passed);
    try field(json_out, "failed");
    try json_out.write(run.failed);
    try field(json_out, "skipped");
    try json_out.write(run.skipped);
    try field(json_out, "cached");
    try json_out.write(run.cached);
    try field(json_out, "found");
    try json_out.write(run.found);
    try field(json_out, "output_tail");
    try json_out.write(run.output_tail);
    try json_out.endObject();
}

fn writeAttention(json_out: *std.json.Stringify, entry: core.Attention) std.json.Stringify.Error!void {
    try json_out.beginObject();
    try field(json_out, "level");
    try json_out.write(@tagName(entry.level));
    try field(json_out, "text");
    try json_out.write(entry.text);
    try field(json_out, "items");
    try json_out.write(entry.items);
    try json_out.endObject();
}

test "review output writes each decision's why and its rejected alternatives" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const names = [_][]const u8{"app::one"};
    const decisions = [_]core.Decision{
        .{ .path = "decisions/unreleased/one.md", .title = "Add one", .changes = &names, .valid = true, .why = "Callers need one." },
        .{ .path = "decisions/unreleased/two.md", .title = "Add two", .changes = &names, .valid = true, .why = "Two.", .rejected = "Three." },
    };
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{ .decisions = &decisions },
        .refusals = &.{},
    };
    const bytes = try json(scratch, review);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"why\":\"Callers need one.\",\"rejected\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"why\":\"Two.\",\"rejected\":\"Three.\"") != null);
}

test "review output counts the changes a decision explains" {
    const names = [_][]const u8{"app::one"};
    const sentence = [_][]const u8{"New function `one() -> int`."};
    const interface = [_]core.Item{
        .{ .name = "app::one", .module = "app", .kind = "function", .change = .added, .sentences = &sentence, .signatures = .{ .signature = "func one() -> int" }, .decision = "Add one" },
        .{ .name = "app::two", .module = "app", .kind = "function", .change = .removed, .sentences = &sentence, .signatures = .{ .signature = "func two() -> int" } },
    };
    const decisions = [_]core.Decision{.{ .path = "decisions/unreleased/one.md", .title = "Add one", .changes = &names, .valid = true }};
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789abcdef", .head = "fedcba9876543210", .working_tree = false },
        .interface = &interface,
        .evidence = .{ .decisions = &decisions },
        .refusals = &.{},
        .facts = .{ .source_changed = true },
    };
    const counts = countsOf(review);
    try std.testing.expectEqual(@as(usize, 1), counts.added);
    try std.testing.expectEqual(@as(usize, 1), counts.removed);
    try std.testing.expectEqual(@as(usize, 1), counts.explained);
    try std.testing.expectEqualStrings("fedcba9", headLabel(review.range));
}

test "review output writes the review-v1 version and the verdict" {
    const a = std.testing.allocator;
    const refusals = [_]core.Refusal{.{ .code = "E_REVIEW_SUMMARY_MISSING", .message = "no note", .path = "main.selka", .line = 3 }};
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{},
        .refusals = &refusals,
        .facts = .{ .body_changed = &.{"app::same"}, .source_changed = true },
    };
    const bytes = try json(a, review);
    defer a.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "{\"version\":\"review-v1\",\"project\":\"app\""));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"verdict\":{\"ok\":false,\"refusals\":[{\"code\":\"E_REVIEW_SUMMARY_MISSING\",\"message\":\"no note\",\"path\":\"main.selka\",\"line\":3}]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"body_changed\":[\"app::same\"],\"source_changed\":true,\"behaviour\":{\"examples_changed\":[]") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"inside\":[],\"generated\":[],\"citations\":{\"added\":[],\"removed\":[]},\"attention\":[]}\n") != null);
}

test "O3 review refusal preserves the source ownership rule in text and JSON" {
    const a = std.testing.allocator;
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "base", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{},
        .refusals = &.{.{ .code = "E_REVIEW_HEAD_UNREADABLE", .source_code = "E_BORROW_SOURCE", .message = "invalid declared source", .rule = .R4 }},
    };
    const rendered = try text(a, review);
    defer a.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "source diagnostic E_BORROW_SOURCE") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "ownership rule R4") != null);
    const bytes = try json(a, review);
    defer a.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"source_code\":\"E_BORROW_SOURCE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"rule\":\"R4\"") != null);
}

fn textAllocations(a: std.mem.Allocator) !void {
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "base", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{},
        .refusals = &.{.{ .code = "E_REVIEW_HEAD_UNREADABLE", .message = "invalid source", .rule = .R4 }},
    };
    const rendered = try text(a, review);
    defer a.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "ownership rule R4") != null);
    var passing = review;
    passing.refusals = &.{};
    passing.interface = &.{.{
        .name = "app::part",
        .module = "app",
        .kind = "function",
        .change = .added,
        .sentences = &.{ "New function", "Returns a fresh value" },
        .signatures = .{ .signature = "func() -> str" },
    }};
    const summary = try text(a, passing);
    defer a.free(summary);
    try std.testing.expect(std.mem.indexOf(u8, summary, "New function; Returns a fresh value") != null);
}

test "O3 review text returns owned bytes and cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, textAllocations, .{});
}

/// `count` added interface items named `app::fN`, each with one sentence and a decision.
fn manyItems(a: std.mem.Allocator, count: usize) Error![]core.Item {
    const items = try a.alloc(core.Item, count);
    for (items, 0..) |*item, index| {
        item.* = .{ .name = try std.fmt.allocPrint(a, "app::f{d}", .{index}), .module = "app", .kind = "function", .change = .added, .sentences = &.{"New function `f()`."}, .signatures = .{ .signature = "func f()" }, .decision = "Add" };
    }
    return items;
}

/// `count` lines of the form `item N`, for an attention entry's items.
fn manyLines(a: std.mem.Allocator, count: usize) Error![][]const u8 {
    const lines = try a.alloc([]const u8, count);
    for (lines, 0..) |*line, index| line.* = try std.fmt.allocPrint(a, "item {d}", .{index});
    return lines;
}

/// `count` edited functions `app::fN` of module `app`, each measured from 4 to 6 lines, one decision point to two.
fn manyFunctions(a: std.mem.Allocator, count: usize) Error![]review_inside.Function {
    const functions = try a.alloc(review_inside.Function, count);
    for (functions, 0..) |*function, index| {
        function.* = .{
            .name = try std.fmt.allocPrint(a, "app::f{d}", .{index}),
            .public = false,
            .state = .changed,
            .location = .{ .file = "app.selka", .line = index + 1 },
            .measure = .{ .lines = .{ .before = 4, .after = 6 }, .decision_points = .{ .before = 1, .after = 2 } },
            .signals = &.{},
            .diff = &.{},
        };
    }
    return functions;
}

test "review output names each edited function on one line and puts test helpers on one line" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const functions = try manyFunctions(scratch, 11);
    const helper = [_]review_inside.Function{.{
        .name = "cli_test::serve_of",
        .public = false,
        .state = .added,
        .location = .{ .file = "cli_test.selka", .line = 1 },
        .measure = .{ .lines = .{ .before = 0, .after = 2 } },
        .signals = &.{},
        .diff = &.{},
    }};
    const all = try std.mem.concat(scratch, review_inside.Function, &.{ functions, &helper });
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{},
        .refusals = &.{},
        .facts = .{ .inside = all },
    };
    const rendered = try text(scratch, review);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  app::f0: edited, lines 4 → 6, decision points 1 → 2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  app::f9: edited, lines 4 → 6, decision points 1 → 2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  app::f10: edited") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  … 1 more\n  test helpers changed: cli_test::serve_of\n") != null);
}

test "review output prints at most thirty lines when the review passes" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const attention = [_]core.Attention{
        .{ .level = .info, .text = "3 existing tests now expect something different", .items = try manyLines(scratch, 9) },
        .{ .level = .warn, .text = "2 tests were removed", .items = try manyLines(scratch, 2) },
    };
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = try manyItems(scratch, 40),
        .evidence = .{},
        .refusals = &.{},
        .facts = .{ .attention = &attention, .tests_run = .{ .found = true, .passed = 4 } },
    };
    const rendered = try text(scratch, review);
    try std.testing.expect(std.mem.count(u8, rendered, "\n") <= max_passing_lines);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "! 3 existing tests now expect something different\n  item 0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  … 4 more\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "review: passes;") != null);
}

test "review output prints each refusal once as an error line and counts the refusals in the attention list" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const refusals = [_]core.Refusal{
        .{ .code = "E_REVIEW_DECISION_MISSING", .message = "public declaration main::run is added", .path = "main.selka", .line = 7 },
        .{ .code = "E_REVIEW_SUMMARY_MISSING", .message = "no change note names this change" },
    };
    var review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{},
        .refusals = &refusals,
    };
    review.facts.attention = try review_attention.build(scratch, review);
    const rendered = try text(scratch, review);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "! 2 refusals block the change; they are listed below\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "main.selka:7: error[E_REVIEW_DECISION_MISSING]: public declaration main::run is added\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\nerror[E_REVIEW_SUMMARY_MISSING]: no change note names this change\n") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, rendered, "public declaration main::run is added"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, rendered, "no change note names this change"));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\n  E_REVIEW") == null);
    const bytes = try json(scratch, review);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"attention\":[{\"level\":\"warn\",\"text\":\"2 refusals block the change; they are listed below\"," ++
        "\"items\":[\"E_REVIEW_DECISION_MISSING: public declaration main::run is added\",\"E_REVIEW_SUMMARY_MISSING: no change note names this change\"]}]") != null);
}

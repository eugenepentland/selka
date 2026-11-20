//! The comparison behind `selka review`: the public interface of two sides, the
//! decisions and change notes the change adds, the source change, and the refusals
//! of the gate (plan section 3.5). Pure over two loaded sides: nothing is read,
//! written or run here.
const std = @import("std");
const review_side = @import("review_side.zig");
const release_decisions = @import("release_decisions.zig");
const change_notes = @import("change_notes.zig");
const baseline = @import("api_diff_baseline.zig");
const types = @import("overview_types.zig");
const sentences = @import("review_sentences.zig");
const review_tests = @import("review_tests.zig");
const review_examples = @import("review_examples.zig");
const review_files = @import("review_files.zig");
const review_inside = @import("review_inside.zig");

/// Allocation is the only failure: every input is already loaded.
pub const Error = std.mem.Allocator.Error;

const code_decision_missing = "E_REVIEW_DECISION_MISSING";
const code_summary_missing = "E_REVIEW_SUMMARY_MISSING";
/// The refusal code of a base side whose declarations do not load.
pub const code_base_unreadable = "E_REVIEW_BASE_UNREADABLE";
/// The refusal code of a head side (a revision or the working tree) whose declarations do not load.
pub const code_head_unreadable = "E_REVIEW_HEAD_UNREADABLE";

/// How a public declaration differs between the base and the head.
pub const Change = enum { added, changed, removed };

/// The commits or working tree a review compares, and whether the head is the working tree.
pub const Range = struct { base: []const u8, head: []const u8, working_tree: bool };

/// The current signature of a declaration, the base signature of a changed or removed
/// one, and the capability types the declaration gained (all of an added function's
/// authority, or the types a changed function's head lists and its base does not).
pub const Signatures = struct { signature: []const u8, old_signature: ?[]const u8 = null, gained_authority: []const []const u8 = &.{} };

/// One public declaration the change adds, changes or removes, with its explanation.
pub const Item = struct {
    name: []const u8,
    module: []const u8,
    kind: []const u8,
    change: Change,
    sentences: []const []const u8,
    signatures: Signatures,
    decision: ?[]const u8 = null,
};

/// One change note in the change: its file, its title and Summary, and whether it is valid.
pub const Note = struct { path: []const u8, title: []const u8, summary: []const u8, valid: bool };

/// One decision file in the change: its file, its title, the names it explains, its Why and
/// Rejected text, and whether it is valid.
pub const Decision = struct { path: []const u8, title: []const u8, changes: []const []const u8, valid: bool, why: []const u8 = "", rejected: ?[]const u8 = null };

/// The change notes and decisions the change adds or edits, in path order.
pub const Evidence = struct { notes: []const Note = &.{}, decisions: []const Decision = &.{} };

/// One reason the gate refuses the change, with its location when it has one.
pub const Refusal = struct {
    code: []const u8,
    message: []const u8,
    name: ?[]const u8 = null,
    path: ?[]const u8 = null,
    line: ?usize = null,
    rule: ?@import("diagnostic.zig").Rule = null,
    source_code: ?[]const u8 = null,
};

/// The tests and docstring examples a change shows differently, each list in name order.
pub const Behaviour = struct {
    examples_changed: []const review_examples.Change = &.{},
    tests_added: []const review_tests.Ref = &.{},
    tests_changed: []const review_tests.Changed = &.{},
    tests_removed: []const review_tests.Ref = &.{},
};

/// How a reader weighs one attention entry: a warning needs a decision, information does not.
pub const Level = enum { warn, info };

/// One entry of the attention list: its level, its sentence and the items the sentence names.
/// When `listed_below` is set the items repeat refusals that the terminal prints in full below
/// the list, so the terminal leaves them out; the JSON keeps them.
pub const Attention = struct { level: Level, text: []const u8, items: []const []const u8, listed_below: bool = false };

/// The files a change touches beyond its interface: the generated sources, and the issue ids
/// that comment lines add and remove.
pub const FileFacts = struct { generated: []const review_files.Generated = &.{}, citations: review_files.Citations = .{} };

/// What a review shows beyond the interface and the gate: the bodies that changed, the
/// functions the change edits, the tests and examples that behave differently, the files it
/// touches beyond its interface, the attention list, and the verdict counts of `--test` when it ran.
pub const Facts = struct {
    body_changed: []const []const u8 = &.{},
    source_changed: bool = false,
    behaviour: Behaviour = .{},
    inside: []const review_inside.Function = &.{},
    files: FileFacts = .{},
    attention: []const Attention = &.{},
    tests_run: ?review_tests.Run = null,
};

/// A complete review: the verdict is `refusals` being empty.
pub const Review = struct {
    project: []const u8,
    range: Range,
    interface: []const Item,
    evidence: Evidence,
    refusals: []const Refusal,
    facts: Facts = .{},
};

/// Everything a review compares: the project as the caller named it, the range and the two sides.
pub const Input = struct {
    project: []const u8,
    range: Range,
    base: *const review_side.Side,
    head: *const review_side.Side,
};

/// One public name the comparison found, its change and the entries it came from.
pub const Found = struct { name: []const u8, kind: []const u8, change: Change, base: ?usize = null, head: ?usize = null };

/// The public names of two sides that differ, and the names whose body alone differs.
pub const Diff = struct { found: []const Found, body: []const []const u8 };

/// Compare two sides and apply the gate. Allocations belong to `a`, normally a command arena.
pub fn compare(a: std.mem.Allocator, input: Input) Error!Review {
    var refusals: std.ArrayList(Refusal) = .empty;
    try unreadableRefusals(a, input, &refusals);
    const decision_files = try newFiles(a, input.head.files.decisions, input.base.files.decisions);
    const note_files = try newFiles(a, input.head.files.notes, input.base.files.notes);
    const evidence = try parseEvidence(a, decision_files, note_files, &refusals);
    const source_changed = !sameFiles(input.base.files.sources, input.head.files.sources);
    if (source_changed and note_files.len == 0) {
        try refusals.append(a, .{
            .code = code_summary_missing,
            .message = try std.fmt.allocPrint(a, "the change touches the project's source and adds no change note; run `selka review draft {s} --name SLUG`", .{input.project}),
        });
    }
    var interface: []const Item = &.{};
    var body: []const []const u8 = &.{};
    if (input.base.state != .unreadable and input.head.state != .unreadable) {
        const diff = try classify(a, entriesOf(input.base), entriesOf(input.head));
        interface = try items(a, input, diff.found, evidence, &refusals);
        body = diff.body;
    }
    return .{
        .project = input.project,
        .range = input.range,
        .interface = interface,
        .evidence = evidence,
        .refusals = refusals.items,
        .facts = .{
            .body_changed = body,
            .source_changed = source_changed,
            .behaviour = try behaviourOf(a, input),
            .inside = try review_inside.compare(a, input.base.files.sources, input.head.files.sources),
            .files = .{
                .generated = try review_files.generatedChanges(a, input.base.files.sources, input.head.files.sources),
                .citations = try review_files.citationChanges(a, input.base.files.sources, input.head.files.sources),
            },
        },
    };
}

/// The behaviour a change shows: the tests of the two sources, and the docstring examples
/// the two overview documents show differently. Examples need both sides to load.
fn behaviourOf(a: std.mem.Allocator, input: Input) Error!Behaviour {
    const tests = try review_tests.compare(a, input.base.files.sources, input.head.files.sources);
    var examples: []const review_examples.Change = &.{};
    if (documentOf(input.base)) |before| {
        if (documentOf(input.head)) |after| examples = try review_examples.compare(a, before, after);
    }
    return .{ .examples_changed = examples, .tests_added = tests.added, .tests_changed = tests.changed, .tests_removed = tests.removed };
}

/// Compare two sets of public entries by identity: additions, removals and interface
/// changes are `found`, and a body-only change is listed by name in `body`. Both
/// lists are in name order.
pub fn classify(a: std.mem.Allocator, base: []const baseline.Entry, head: []const baseline.Entry) Error!Diff {
    var known: std.StringHashMapUnmanaged(usize) = .empty;
    for (base, 0..) |entry, index| try known.put(a, entry.identity, index);
    const seen = try a.alloc(bool, base.len);
    @memset(seen, false);
    var found: std.ArrayList(Found) = .empty;
    var body: std.ArrayList([]const u8) = .empty;
    for (head, 0..) |entry, head_index| {
        const base_index = known.get(entry.identity) orelse {
            try found.append(a, .{ .name = entry.display, .kind = entry.kind, .change = .added, .head = head_index });
            continue;
        };
        seen[base_index] = true;
        const before = base[base_index];
        if (!std.mem.eql(u8, before.interface, entry.interface)) {
            try found.append(a, .{ .name = entry.display, .kind = entry.kind, .change = .changed, .base = base_index, .head = head_index });
        } else if (!std.mem.eql(u8, before.body, entry.body)) {
            try body.append(a, entry.display);
        }
    }
    for (base, 0..) |entry, index| {
        if (seen[index]) continue;
        try found.append(a, .{ .name = entry.display, .kind = entry.kind, .change = .removed, .base = index });
    }
    std.mem.sort(Found, found.items, {}, foundLess);
    std.mem.sort([]const u8, body.items, {}, textLess);
    return .{ .found = found.items, .body = body.items };
}

/// The head files whose bytes match no base file, in path order. A file that a
/// release only moved, unchanged, is therefore not in the change.
fn newFiles(a: std.mem.Allocator, head: []const review_side.File, base: []const review_side.File) Error![]const review_side.File {
    var known: std.StringHashMapUnmanaged(void) = .empty;
    for (base) |file| try known.put(a, file.bytes, {});
    var out: std.ArrayList(review_side.File) = .empty;
    for (head) |file| {
        if (!known.contains(file.bytes)) try out.append(a, file);
    }
    return out.items;
}

/// Whether two sorted file lists hold the same paths with the same bytes.
fn sameFiles(before: []const review_side.File, after: []const review_side.File) bool {
    if (before.len != after.len) return false;
    for (before, after) |left, right| {
        if (!std.mem.eql(u8, left.path, right.path) or !std.mem.eql(u8, left.bytes, right.bytes)) return false;
    }
    return true;
}

/// Parse the change's decisions (with the pending rules) and notes. Every issue
/// becomes a refusal; a decision or note with issues is still returned, marked invalid.
fn parseEvidence(a: std.mem.Allocator, decision_files: []const review_side.File, note_files: []const review_side.File, refusals: *std.ArrayList(Refusal)) Error!Evidence {
    const decision_items = try a.alloc(Decision, decision_files.len);
    for (decision_files, decision_items) |file, *out| {
        const parsed = try release_decisions.parse(a, file.path, file.bytes, true);
        out.* = .{
            .path = file.path,
            .title = parsed.decision.metadata.title,
            .changes = parsed.decision.changes,
            .valid = parsed.decision.valid,
            .why = parsed.decision.metadata.why,
            .rejected = parsed.decision.metadata.rejected,
        };
        for (parsed.issues) |issue| try refusals.append(a, .{ .code = issue.code, .message = issue.message, .path = issue.path, .line = issue.line });
    }
    const note_items = try a.alloc(Note, note_files.len);
    for (note_files, note_items) |file, *out| {
        const parsed = try change_notes.parse(a, file.path, file.bytes);
        out.* = .{ .path = file.path, .title = parsed.note.title, .summary = parsed.note.summary, .valid = parsed.issues.len == 0 };
        for (parsed.issues) |issue| try refusals.append(a, .{ .code = issue.code, .message = issue.message, .path = issue.path, .line = issue.line });
    }
    return .{ .notes = note_items, .decisions = decision_items };
}

/// One refusal for each side whose declarations did not load.
fn unreadableRefusals(a: std.mem.Allocator, input: Input, refusals: *std.ArrayList(Refusal)) Error!void {
    if (input.base.state == .unreadable) {
        try refusals.append(a, try unreadableRefusal(a, code_base_unreadable, "base revision", input.base.state.unreadable));
    }
    if (input.head.state == .unreadable) {
        const label = if (input.range.working_tree) "working tree" else "head revision";
        try refusals.append(a, try unreadableRefusal(a, code_head_unreadable, label, input.head.state.unreadable));
    }
}

fn unreadableRefusal(a: std.mem.Allocator, code: []const u8, label: []const u8, problem: review_side.Problem) Error!Refusal {
    if (problem.project_module) return .{
        .code = code,
        .rule = problem.rule,
        .source_code = if (problem.code.len != 0) problem.code else null,
        .message = try std.fmt.allocPrint(a, "a project module does not load: {s}; repair the source before reviewing", .{problem.message}),
    };
    return .{
        .code = code,
        .rule = problem.rule,
        .source_code = if (problem.code.len != 0) problem.code else null,
        .message = try std.fmt.allocPrint(a, "the {s} declarations do not load: {s}; repair the source before reviewing", .{ label, problem.message }),
        .path = if (problem.path.len != 0) problem.path else null,
        .line = if (problem.line != 0) problem.line else null,
    };
}

/// One item per found name, with its sentences, signatures and explaining decision,
/// and one refusal for each public change that no valid in-range decision names.
fn items(a: std.mem.Allocator, input: Input, found: []const Found, evidence: Evidence, refusals: *std.ArrayList(Refusal)) Error![]const Item {
    const base_document = documentOf(input.base);
    const head_document = documentOf(input.head);
    // A project absent at the base is new: any valid decision of the change explains it.
    const new_project_title: ?[]const u8 = if (input.base.state == .absent) firstValid(evidence) else null;
    var out: std.ArrayList(Item) = .empty;
    for (found) |entry| {
        const base_decl = if (base_document) |document| review_side.declaration(document, entry.name) else null;
        const head_decl = if (head_document) |document| review_side.declaration(document, entry.name) else null;
        const decision = decisionFor(evidence, entry.name) orelse new_project_title;
        if (decision == null) {
            try refusals.append(a, .{
                .code = code_decision_missing,
                .name = entry.name,
                .message = try std.fmt.allocPrint(a, "public declaration {s} is {s} and no decision in this change names it; run `selka release draft {s} --name SLUG`", .{ entry.name, @tagName(entry.change), input.project }),
            });
        }
        const shown = if (entry.change == .removed) base_decl else head_decl;
        var old_signature: ?[]const u8 = null;
        if (entry.change != .added) {
            if (base_decl) |decl| old_signature = decl.signature;
        }
        try out.append(a, .{
            .name = entry.name,
            .module = moduleOf(entry.name),
            .kind = entry.kind,
            .change = entry.change,
            .sentences = try sentencesFor(a, entry.change, base_decl, head_decl),
            .signatures = .{
                .signature = if (shown) |decl| decl.signature else entry.name,
                .old_signature = old_signature,
                .gained_authority = try gainedAuthority(a, entry.change, base_decl, head_decl),
            },
            .decision = decision,
        });
    }
    return out.items;
}

/// The sentences of one change: the review_sentences rows for an added, removed or
/// changed declaration, or the fallback when the two declarations are not both known
/// or name no difference.
fn sentencesFor(a: std.mem.Allocator, change: Change, base_decl: ?types.Declaration, head_decl: ?types.Declaration) Error![]const []const u8 {
    if (change == .added) {
        if (head_decl) |decl| return sentences.added(a, decl);
    } else if (change == .removed) {
        if (base_decl) |decl| return sentences.removed(a, decl);
    } else if (base_decl != null and head_decl != null) {
        const clauses = try sentences.changed(a, base_decl.?, head_decl.?);
        if (clauses.len != 0) return clauses;
    }
    const out = try a.alloc([]const u8, 1);
    out[0] = sentences.fallback;
    return out;
}

/// The capability types a declaration gained: all of an added function's authority, or
/// for a changed one the types its head lists and its base does not. Nothing for a removed one.
fn gainedAuthority(a: std.mem.Allocator, change: Change, base_decl: ?types.Declaration, head_decl: ?types.Declaration) Error![]const []const u8 {
    if (change == .removed) return &.{};
    const head_function = (head_decl orelse return &.{}).details.function orelse return &.{};
    var before: []const types.Parameter = &.{};
    if (change == .changed) {
        if (base_decl) |decl| {
            if (decl.details.function) |function| before = function.authority;
        }
    }
    var out: std.ArrayList([]const u8) = .empty;
    for (head_function.authority) |parameter| {
        if (!hasType(before, parameter.type)) try out.append(a, parameter.type);
    }
    return out.items;
}

/// Whether one of `parameters` has the capability type `name`.
fn hasType(parameters: []const types.Parameter, name: []const u8) bool {
    for (parameters) |parameter| {
        if (std.mem.eql(u8, parameter.type, name)) return true;
    }
    return false;
}

/// The title of the first valid decision of the change that names `name`.
fn decisionFor(evidence: Evidence, name: []const u8) ?[]const u8 {
    for (evidence.decisions) |decision| {
        if (!decision.valid) continue;
        for (decision.changes) |changed| {
            if (std.mem.eql(u8, changed, name)) return decision.title;
        }
    }
    return null;
}

/// The title of the first valid decision of the change, whatever it names.
fn firstValid(evidence: Evidence) ?[]const u8 {
    for (evidence.decisions) |decision| {
        if (decision.valid) return decision.title;
    }
    return null;
}

/// The module part of a `module::name` qualified name.
fn moduleOf(name: []const u8) []const u8 {
    const separator = std.mem.indexOf(u8, name, "::") orelse return "";
    return name[0..separator];
}

/// The public entries of a side that loaded; an absent side has none.
fn entriesOf(side: *const review_side.Side) []const baseline.Entry {
    return switch (side.state) {
        .loaded => |*loaded| loaded.entries,
        else => &.{},
    };
}

/// The overview document of a side that loaded.
fn documentOf(side: *const review_side.Side) ?*const types.Document {
    return switch (side.state) {
        .loaded => |*loaded| &loaded.document,
        else => null,
    };
}

fn foundLess(_: void, left: Found, right: Found) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn textLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn makeEntry(identity: []const u8, display: []const u8, interface: []const u8, body: []const u8) baseline.Entry {
    return .{ .identity = identity, .display = display, .kind = "function", .interface = interface, .body = body };
}

test "review core classifies added, removed, changed and body-only public names" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const base = [_]baseline.Entry{
        makeEntry("i::gone", "app::gone", "iface-a", "body-a"),
        makeEntry("i::same", "app::same", "iface-b", "body-b"),
        makeEntry("i::moved", "app::moved", "iface-c", "body-c"),
    };
    const head = [_]baseline.Entry{
        makeEntry("i::new", "app::new", "iface-d", "body-d"),
        makeEntry("i::same", "app::same", "iface-b", "body-b2"),
        makeEntry("i::moved", "app::moved", "iface-c2", "body-c"),
    };
    const diff = try classify(scratch, &base, &head);
    try std.testing.expectEqual(@as(usize, 3), diff.found.len);
    try std.testing.expectEqualStrings("app::gone", diff.found[0].name);
    try std.testing.expectEqual(Change.removed, diff.found[0].change);
    try std.testing.expectEqualStrings("app::moved", diff.found[1].name);
    try std.testing.expectEqual(Change.changed, diff.found[1].change);
    try std.testing.expectEqualStrings("app::new", diff.found[2].name);
    try std.testing.expectEqual(Change.added, diff.found[2].change);
    try std.testing.expectEqual(@as(usize, 1), diff.body.len);
    try std.testing.expectEqualStrings("app::same", diff.body[0]);
}

test "review core finds no difference between identical entry lists" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const entries = [_]baseline.Entry{makeEntry("i::one", "app::one", "iface", "body")};
    const diff = try classify(arena.allocator(), &entries, &entries);
    try std.testing.expectEqual(@as(usize, 0), diff.found.len);
    try std.testing.expectEqual(@as(usize, 0), diff.body.len);
}

test "review core names the module of a qualified name" {
    try std.testing.expectEqualStrings("framing", moduleOf("framing::next_request"));
    try std.testing.expectEqualStrings("", moduleOf("no_module"));
}

test "review core treats a moved decision file as no change" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const base = [_]review_side.File{.{ .path = "decisions/unreleased/x.md", .bytes = "same bytes" }};
    const head = [_]review_side.File{ .{ .path = "decisions/0.2/x.md", .bytes = "same bytes" }, .{ .path = "decisions/unreleased/y.md", .bytes = "new bytes" } };
    const fresh = try newFiles(scratch, &head, &base);
    try std.testing.expectEqual(@as(usize, 1), fresh.len);
    try std.testing.expectEqualStrings("decisions/unreleased/y.md", fresh[0].path);
    try std.testing.expect(sameFiles(&base, &[_]review_side.File{.{ .path = "decisions/unreleased/x.md", .bytes = "same bytes" }}));
    try std.testing.expect(!sameFiles(&base, &head));
}

test "review core explains a change with the first valid decision that names it" {
    const names = [_][]const u8{"app::answer"};
    const decisions_list = [_]Decision{
        .{ .path = "decisions/unreleased/bad.md", .title = "Bad", .changes = &names, .valid = false },
        .{ .path = "decisions/unreleased/good.md", .title = "Good", .changes = &names, .valid = true },
    };
    const evidence: Evidence = .{ .decisions = &decisions_list };
    try std.testing.expectEqualStrings("Good", decisionFor(evidence, "app::answer").?);
    try std.testing.expect(decisionFor(evidence, "app::other") == null);
    try std.testing.expectEqualStrings("Good", firstValid(evidence).?);
}

test "review core lists the capability types a changed function gains" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const base_authority = [_]types.Parameter{.{ .name = "clock", .type = "Clock" }};
    const head_authority = [_]types.Parameter{ .{ .name = "clock", .type = "Clock" }, .{ .name = "fs", .type = "Filesystem" } };
    const gained = try gainedAuthority(scratch, .changed, declarationWith(&base_authority), declarationWith(&head_authority));
    try std.testing.expectEqual(@as(usize, 1), gained.len);
    try std.testing.expectEqualStrings("Filesystem", gained[0]);
    const added = try gainedAuthority(scratch, .added, null, declarationWith(&head_authority));
    try std.testing.expectEqual(@as(usize, 2), added.len);
    try std.testing.expectEqual(@as(usize, 0), (try gainedAuthority(scratch, .removed, declarationWith(&head_authority), null)).len);
}

/// A function declaration with the given authority, for the gained-authority test.
fn declarationWith(authority: []const types.Parameter) types.Declaration {
    return .{
        .name = "main::run",
        .kind = "function",
        .signature = "func run()",
        .doc = "",
        .details = .{ .function = .{ .writes = &.{}, .authority = authority, .tests = &.{}, .fails = null, .hole = false, .examples = 0, .waiver = null } },
        .decisions = &.{},
    };
}

//! The attention list of a review: what a reader must decide before the change lands, in
//! the order the change-review plan gives (section 3.2, item 3). Pure over a finished
//! review. The possible-patching signals of section 3.4 come after the examples and before
//! the generated files.
const std = @import("std");
const core = @import("review_core.zig");
const review_inside = @import("review_inside.zig");
const review_tests = @import("review_tests.zig");
const review_examples = @import("review_examples.zig");
const review_files = @import("review_files.zig");

/// Allocation is the only failure: the entries and their items are built in memory.
pub const Error = std.mem.Allocator.Error;

/// The attention entries of a review, in the order a reader decides them.
pub fn build(a: std.mem.Allocator, review: core.Review) Error![]const core.Attention {
    var out: std.ArrayList(core.Attention) = .empty;
    try refusalEntry(a, review.refusals, &out);
    try unavailableEntry(a, review.refusals, &out);
    try authorityEntry(a, review.interface, &out);
    try testEntries(a, review.facts.behaviour, &out);
    try exampleEntry(a, review.facts.behaviour, &out);
    try patchingEntry(a, review.facts.inside, &out);
    try generatedEntry(a, review.facts.files.generated, &out);
    return out.items;
}

/// One warning for the gate's refusals: a count that points to the `error[…]` lines the
/// terminal prints below the list. Its items name each refusal by its code and message, for the JSON.
fn refusalEntry(a: std.mem.Allocator, refusals: []const core.Refusal, out: *std.ArrayList(core.Attention)) Error!void {
    if (refusals.len == 0) return;
    const items = try a.alloc([]const u8, refusals.len);
    for (refusals, items) |refusal, *item| item.* = try std.fmt.allocPrint(a, "{s}: {s}", .{ refusal.code, refusal.message });
    const text = if (refusals.len == 1)
        "1 refusal blocks the change; it is listed below"
    else
        try std.fmt.allocPrint(a, "{d} refusals block the change; they are listed below", .{refusals.len});
    try out.append(a, .{ .level = .warn, .text = text, .items = items, .listed_below = true });
}

/// One warning for each side whose declarations did not load: the facts that need both
/// sides' declarations are then not compared. Its items are the refusals' messages, which
/// the terminal prints below the list.
fn unavailableEntry(a: std.mem.Allocator, refusals: []const core.Refusal, out: *std.ArrayList(core.Attention)) Error!void {
    var items: std.ArrayList([]const u8) = .empty;
    for (refusals) |refusal| {
        const unreadable = std.mem.eql(u8, refusal.code, core.code_base_unreadable) or std.mem.eql(u8, refusal.code, core.code_head_unreadable);
        if (unreadable) try items.append(a, refusal.message);
    }
    if (items.items.len == 0) return;
    const sides = if (items.items.len == 1) "side did not load" else "sides did not load";
    const text = try std.fmt.allocPrint(a, "{d} {s}, so the public interface, bodies, examples and authority are not compared", .{ items.items.len, sides });
    try out.append(a, .{ .level = .warn, .text = text, .items = items.items, .listed_below = true });
}

/// One information entry for the public functions that gained a capability: an added
/// function with any authority, or a changed one whose head lists a type its base lacks.
fn authorityEntry(a: std.mem.Allocator, interface: []const core.Item, out: *std.ArrayList(core.Attention)) Error!void {
    var items: std.ArrayList([]const u8) = .empty;
    for (interface) |item| {
        const gained = item.signatures.gained_authority;
        if (gained.len == 0) continue;
        const verb = if (item.change == .changed) "now needs" else "needs";
        try items.append(a, try std.fmt.allocPrint(a, "{s}: {s} {s}", .{ item.name, verb, try codedList(a, gained) }));
    }
    if (items.items.len == 0) return;
    try out.append(a, .{ .level = .info, .text = "New authority: these functions can now reach the outside world", .items = items.items });
}

/// Information for the existing tests whose expectations changed, then a warning for
/// the tests that were removed.
fn testEntries(a: std.mem.Allocator, behaviour: core.Behaviour, out: *std.ArrayList(core.Attention)) Error!void {
    if (behaviour.tests_changed.len != 0) {
        const items = try a.alloc([]const u8, behaviour.tests_changed.len);
        for (behaviour.tests_changed, items) |changed, *item| item.* = try qualified(a, changed.module, changed.name);
        const text = if (items.len == 1) "1 existing test now expects something different" else try std.fmt.allocPrint(a, "{d} existing tests now expect something different", .{items.len});
        try out.append(a, .{ .level = .info, .text = text, .items = items });
    }
    if (behaviour.tests_removed.len != 0) {
        const items = try a.alloc([]const u8, behaviour.tests_removed.len);
        for (behaviour.tests_removed, items) |removed, *item| item.* = try qualified(a, removed.module, removed.name);
        const text = if (items.len == 1) "1 test was removed" else try std.fmt.allocPrint(a, "{d} tests were removed", .{items.len});
        try out.append(a, .{ .level = .warn, .text = text, .items = items });
    }
}

/// Information for the docstring examples whose output changed, each named with its source.
fn exampleEntry(a: std.mem.Allocator, behaviour: core.Behaviour, out: *std.ArrayList(core.Attention)) Error!void {
    const changes = behaviour.examples_changed;
    if (changes.len == 0) return;
    const items = try a.alloc([]const u8, changes.len);
    for (changes, items) |change, *item| item.* = try std.fmt.allocPrint(a, "{s}: `{s}`", .{ change.name, change.source });
    const text = if (changes.len == 1) "1 docstring example now shows a different result" else try std.fmt.allocPrint(a, "{d} docstring examples now show a different result", .{changes.len});
    try out.append(a, .{ .level = .info, .text = text, .items = items });
}

/// One warning for the possible-patching signals of the changed functions (plan section 3.4),
/// each item naming its function and its sentence. The signals never block the change.
fn patchingEntry(a: std.mem.Allocator, functions: []const review_inside.Function, out: *std.ArrayList(core.Attention)) Error!void {
    var items: std.ArrayList([]const u8) = .empty;
    for (functions) |function| {
        for (function.signals) |signal| try items.append(a, try std.fmt.allocPrint(a, "{s}: {s}", .{ function.name, signal.text }));
    }
    if (items.items.len == 0) return;
    try out.append(a, .{ .level = .warn, .text = "Possible patching instead of restructuring (heuristic)", .items = items.items });
}

/// Information for the generated sources that changed, each with its line counts.
fn generatedEntry(a: std.mem.Allocator, generated: []const review_files.Generated, out: *std.ArrayList(core.Attention)) Error!void {
    if (generated.len == 0) return;
    const items = try a.alloc([]const u8, generated.len);
    for (generated, items) |file, *item| item.* = try std.fmt.allocPrint(a, "{s}: {d} lines before, {d} after", .{ file.path, file.lines_before, file.lines_after });
    const text = if (generated.len == 1) "1 generated file changed; review its generator instead" else try std.fmt.allocPrint(a, "{d} generated files changed; review their generator instead", .{generated.len});
    try out.append(a, .{ .level = .info, .text = text, .items = items });
}

/// The capability types as a list of code spans: `Filesystem`, `Clock`.
fn codedList(a: std.mem.Allocator, names: []const []const u8) Error![]const u8 {
    const coded = try a.alloc([]const u8, names.len);
    for (names, coded) |name, *span| span.* = try std.fmt.allocPrint(a, "`{s}`", .{name});
    return std.mem.join(a, ", ", coded);
}

/// A test or declaration name qualified by its module: `module::name`.
fn qualified(a: std.mem.Allocator, module: []const u8, name: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}::{s}", .{ module, name });
}

test "review attention lists refusals, authority, tests, examples and generated files in order" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const refusals = [_]core.Refusal{.{ .code = "E_REVIEW_DECISION_MISSING", .message = "public declaration main::run is added" }};
    const gained = [_][]const u8{ "Filesystem", "Clock" };
    const interface = [_]core.Item{.{ .name = "main::run", .module = "main", .kind = "function", .change = .added, .sentences = &.{}, .signatures = .{ .signature = "func run()", .gained_authority = &gained } }};
    const changed = [_]review_tests.Changed{.{ .module = "cli_test", .name = "test_serve", .diff = &.{} }};
    const removed = [_]review_tests.Ref{.{ .module = "cli_test", .name = "test_old" }};
    const examples = [_]review_examples.Change{.{ .name = "main::answer", .source = "answer()", .old = "42", .new = "41" }};
    const generated = [_]review_files.Generated{.{ .path = "ports.selka", .first_line = "# GENERATED by gen_ports.py", .lines_before = 3, .lines_after = 5 }};
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = &interface,
        .evidence = .{},
        .refusals = &refusals,
        .facts = .{ .behaviour = .{ .examples_changed = &examples, .tests_changed = &changed, .tests_removed = &removed }, .files = .{ .generated = &generated } },
    };
    const entries = try build(scratch, review);
    try std.testing.expectEqual(@as(usize, 6), entries.len);
    try std.testing.expectEqualStrings("1 refusal blocks the change; it is listed below", entries[0].text);
    try std.testing.expect(entries[0].listed_below);
    try std.testing.expectEqualStrings("E_REVIEW_DECISION_MISSING: public declaration main::run is added", entries[0].items[0]);
    try std.testing.expectEqualStrings("main::run: needs `Filesystem`, `Clock`", entries[1].items[0]);
    try std.testing.expectEqualStrings("1 existing test now expects something different", entries[2].text);
    try std.testing.expectEqualStrings("cli_test::test_serve", entries[2].items[0]);
    try std.testing.expectEqualStrings("1 test was removed", entries[3].text);
    try std.testing.expectEqual(core.Level.warn, entries[3].level);
    try std.testing.expectEqualStrings("main::answer: `answer()`", entries[4].items[0]);
    try std.testing.expectEqualStrings("1 generated file changed; review its generator instead", entries[5].text);
}

test "review attention lists the possible-patching signals after the examples" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const signals = [_]review_inside.Signal{.{ .kind = .flag, .text = "takes a new bool parameter `verbose` and branches on it" }};
    const inside = [_]review_inside.Function{.{
        .name = "cli::announce",
        .public = false,
        .state = .changed,
        .location = .{ .file = "cli.selka", .line = 1 },
        .measure = .{},
        .signals = &signals,
        .diff = &.{},
    }};
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{},
        .refusals = &.{},
        .facts = .{ .inside = &inside },
    };
    const entries = try build(arena.allocator(), review);
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(core.Level.warn, entries[0].level);
    try std.testing.expectEqualStrings("Possible patching instead of restructuring (heuristic)", entries[0].text);
    try std.testing.expectEqualStrings("cli::announce: takes a new bool parameter `verbose` and branches on it", entries[0].items[0]);
}

test "review attention says how many sides did not load and leaves out an empty list" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const refusals = [_]core.Refusal{
        .{ .code = core.code_base_unreadable, .message = "the base revision declarations do not load: x" },
        .{ .code = core.code_head_unreadable, .message = "the working tree declarations do not load: y" },
    };
    const review: core.Review = .{
        .project = "app",
        .range = .{ .base = "0123456789", .head = "working tree", .working_tree = true },
        .interface = &.{},
        .evidence = .{},
        .refusals = &refusals,
    };
    const entries = try build(arena.allocator(), review);
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expectEqualStrings("2 sides did not load, so the public interface, bodies, examples and authority are not compared", entries[1].text);
    try std.testing.expectEqual(@as(usize, 2), entries[1].items.len);
    try std.testing.expect(entries[1].listed_below);
    const clean: core.Review = .{ .project = "app", .range = review.range, .interface = &.{}, .evidence = .{}, .refusals = &.{} };
    try std.testing.expectEqual(@as(usize, 0), (try build(arena.allocator(), clean)).len);
}

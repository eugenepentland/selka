//! Fault injection for the ownership validator (docs/design/ownership-certificates.md §5, plan C2.3): the certificates the
//! compiler makes for a set of programs are accepted, and every way of breaking one of them with a single edit
//! (`ownership_mutants.zig`) is rejected, each class by the judgment that names it.
const std = @import("std");
const form = @import("ownership_function.zig");
const validate = @import("validate_ownership.zig");
const pipeline = @import("validate_ownership_pipeline_test.zig");
const edits = @import("ownership_mutants.zig");

const Allocator = std.mem.Allocator;
const Check = validate.Check;
const Class = edits.Class;
const Mutants = edits.Mutants;
const mutate = edits.mutate;

/// What a class of fault produced across the corpus: how many mutants, how many of them the validator rejected with
/// one of the judgments the class allows, how many it rejected with another, and how many it accepted.
const Tally = struct { made: usize = 0, named: usize = 0, other: usize = 0, accepted: usize = 0, first_other: ?Check = null };

// ---- running them ------------------------------------------------------------------------------------

/// Whether `check` is one of `allowed`.
fn allows(allowed: []const Check, check: Check) bool {
    return std.mem.indexOfScalar(Check, allowed, check) != null;
}

/// Judge each mutant: how many the validator rejects with a judgment `allowed` names, how many with another, how many it
/// accepts.
fn judge(a: Allocator, mutants: []const form.Function, allowed: []const Check, counts: *Tally) !void {
    for (mutants) |mutant| {
        counts.made += 1;
        switch (try validate.validate(a, mutant)) {
            .accepted, .unchecked => counts.accepted += 1,
            .rejected => |failure| if (allows(allowed, failure.check)) {
                counts.named += 1;
            } else {
                counts.other += 1;
                counts.first_other = counts.first_other orelse failure.check;
            },
        }
    }
}

/// Mutate every function of the corpus programs in `class` and count what the validator says of each mutant.
fn tally(a: Allocator, class: Class, allowed: []const Check) !Tally {
    var counts: Tally = .{};
    for (pipeline.programs) |program| {
        for (try pipeline.functionsOf(a, program)) |function| {
            var mutants: Mutants = .empty;
            try mutate(a, class, function, &mutants);
            try judge(a, mutants.items, allowed, &counts);
        }
    }
    return counts;
}

/// The class produced mutants and the validator rejected every one with a judgment that names the fault.
fn expectRejected(gpa: Allocator, class: Class, allowed: []const Check) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const counts = try tally(arena.allocator(), class, allowed);
    try std.testing.expect(counts.made > 0);
    try std.testing.expectEqual(@as(usize, 0), counts.accepted);
    try std.testing.expectEqual(@as(?Check, null), counts.first_other);
    try std.testing.expectEqual(counts.made, counts.named);
}

/// How many functions of the corpus programs there are, and how many of them the validator rejects as they are.
fn cleanCorpus(a: Allocator) !struct { seen: usize, rejected: usize } {
    var seen: usize = 0;
    var rejected: usize = 0;
    for (pipeline.programs) |program| {
        for (try pipeline.functionsOf(a, program)) |function| {
            seen += 1;
            switch (try validate.validate(a, function)) {
                .accepted, .unchecked => {},
                .rejected => rejected += 1,
            }
        }
    }
    return .{ .seen = seen, .rejected = rejected };
}

test "the certificates of the corpus programs are accepted before any fault is injected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const clean = try cleanCorpus(arena.allocator());
    try std.testing.expect(clean.seen > 0);
    try std.testing.expectEqual(@as(usize, 0), clean.rejected);
}

test "a deleted drop leaves an owner that is never destroyed" {
    try expectRejected(std.testing.allocator, .delete_drop, &.{.j2});
}

test "a duplicated drop destroys an owner twice" {
    try expectRejected(std.testing.allocator, .duplicate_drop, &.{ .j2, .j3 });
}

// A drop moved above a use fails J3 at the read of the destroyed value, or J4 where that value owns a view the use reads
// first: since FR59 `parallel.map` takes its input as a view and its owner (`call map(%view, f, %owner)`), so the
// owner's drop moved above that call leaves the view's loan outliving its root.
test "a drop moved above a use leaves a read of a destroyed value" {
    try expectRejected(std.testing.allocator, .drop_above_use, &.{ .j3, .j4 });
}

test "a consumed borrowed parameter is refused" {
    try expectRejected(std.testing.allocator, .consume_borrowed_parameter, &.{.j5});
}

// A mutant that destroys the owner of a live view fails J4 at the view, J3 where the owner itself is read afterwards, and J8
// where a take of the owner is still open.
test "an owner destroyed while a view of it is live is refused" {
    try expectRejected(std.testing.allocator, .destroy_owner_of_live_view, &.{ .j3, .j4, .j8 });
}

test "a borrowed argument marked consumed is refused" {
    try expectRejected(std.testing.allocator, .consume_borrowed_argument, &.{ .j1, .j5 });
}

test "a borrowed value returned outside the result's from is refused" {
    try expectRejected(std.testing.allocator, .return_outside_from, &.{.j5});
}

test "a stack value that escapes by a return or a consuming call is refused" {
    try expectRejected(std.testing.allocator, .stack_escape, &.{.j7});
}

test "a take from a borrowed container is refused" {
    try expectRejected(std.testing.allocator, .take_from_borrowed, &.{ .j5, .j8 });
}

test "a container dropped with an open take is refused" {
    try expectRejected(std.testing.allocator, .drop_container_with_open_take, &.{.j8});
}

test "a second take of a pending slot is refused" {
    try expectRejected(std.testing.allocator, .second_take_of_pending_slot, &.{.j8});
}

test "a slot taken while a borrow of it is still read is refused" {
    try expectRejected(std.testing.allocator, .take_under_loan, &.{ .j4, .j8 });
}

test "a lender destroyed before its group is joined is refused" {
    try expectRejected(std.testing.allocator, .drop_lender_before_join, &.{.j4});
}

test "a lent slot taken before its group is joined is refused" {
    try expectRejected(std.testing.allocator, .take_lent_slot_before_join, &.{.j4});
}

test "a group used after it was joined is refused" {
    try expectRejected(std.testing.allocator, .use_group_after_join, &.{ .j2, .j3 });
}

test "an owner a trap block uses, abandoned on the edge into it, is refused" {
    try expectRejected(std.testing.allocator, .abandon_used_owner, &.{ .j2, .j3, .j4 });
}

test "an owner abandoned on an edge into a block the function can return from is refused" {
    try expectRejected(std.testing.allocator, .abandon_outside_region, &.{.j2});
}

test "a group abandoned on an edge into a trap block is refused" {
    try expectRejected(std.testing.allocator, .abandon_group, &.{.j2});
}

test "a call that reads one value fewer than its callee has parameters is refused" {
    try expectRejected(std.testing.allocator, .call_loses_argument, &.{.j1});
}

test "a callee table entry that returns something else than its calls get is refused" {
    try expectRejected(std.testing.allocator, .call_result_flipped, &.{.j1});
}

test "a call that names no callee is refused" {
    try expectRejected(std.testing.allocator, .call_names_no_callee, &.{.j1});
}

test "a constructor that reads a borrow of an owner dropped after it is refused (construct-read, the plan of FX6)" {
    try expectRejected(std.testing.allocator, .construct_reads_dropped_owner, &.{.j6});
}

/// How many mutants of `class` the corpus programs give, and how many of them a build's validator (the construct-read rule
/// counting, `validate.build_mode`) accepts.
fn acceptedByBuilds(a: Allocator, class: Class) !struct { made: usize, accepted: usize, counted: u32 } {
    var made: usize = 0;
    var accepted: usize = 0;
    var counted: u32 = 0;
    for (pipeline.programs) |program| {
        for (try pipeline.functionsOf(a, program)) |function| {
            var mutants: Mutants = .empty;
            try mutate(a, class, function, &mutants);
            for (mutants.items) |mutant| {
                made += 1;
                const verdict = try validate.validateWith(a, mutant, .{ .construct_read = .count, .counted = &counted });
                accepted += @intFromBool(verdict == .accepted);
            }
        }
    }
    return .{ .made = made, .accepted = accepted, .counted = counted };
}

// The rule is the only judgment that refuses the class: with it counting, as a build runs it, every mutant is accepted and
// counted once.
test "only the construct-read rule sees a constructor read a borrow of an owner it does not take" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const counts = try acceptedByBuilds(arena.allocator(), .construct_reads_dropped_owner);
    try std.testing.expect(counts.made > 0);
    try std.testing.expectEqual(counts.made, counts.accepted);
    try std.testing.expectEqual(@as(u32, @intCast(counts.made)), counts.counted);
}

test "an owned constructor that holds as a loan a borrow it does not mark a view is refused (construct-read, condition 2)" {
    try expectRejected(std.testing.allocator, .view_unmarked, &.{.j6});
}

// Phase 2 of lane VAL: only the view part of condition 2 sees the class. With the rule counting, every mutant is accepted.
test "only the view part of the construct-read rule sees an aggregate hold a borrow that is not a view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const counts = try acceptedByBuilds(arena.allocator(), .view_unmarked);
    try std.testing.expect(counts.made > 0);
    try std.testing.expectEqual(counts.made, counts.accepted);
    try std.testing.expectEqual(@as(u32, @intCast(counts.made)), counts.counted);
}

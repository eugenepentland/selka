//! `selka check` and the build agree over the guest corpus (lane CB, 9 November 2026). Every top-level file of the language
//! suites and of `test/fixtures/check-build` is checked the way `selka check` checks a library; a file the check accepts is
//! then lowered with every function of its own module as a root, each lowered as a callee (a test build lowers only what its
//! tests reach), checked by
//! the IR verifier, run through the Core passes a build runs (the ownership schedule among them), verified again, and judged
//! by rule C's hidden-copy check, which `--verify-facts` runs (lane HC). A function the check accepted and the build refuses
//! fails the test, named with its file and the refusal.
const std = @import("std");
const product = @import("selka").product;
const typed = @import("selka").typed;
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const own = @import("own.zig");
const verify_ir = @import("verify_ir.zig");
const pipeline = @import("pipeline.zig");

/// One part of the corpus: the top-level `.selka` files of `directory` whose names start at or after `first` and before `last`
/// (a byte), so the language suite splits across the core shards.
const Part = struct { directory: []const u8, first: u8 = 0, last: u8 = 0xff };

/// What one file came to: refused by the check (nothing to compare), built, or accepted by the check and refused by the build.
const Outcome = enum { check_refused, built, disagreed };

/// The functions of the entry module: no other module's prefix, no specialization, and a body the build lowers.
fn roots(a: std.mem.Allocator, program: typed.Program, entry: []const u8) ![]const typed.FunctionId {
    var found: std.ArrayList(typed.FunctionId) = .empty;
    for (program.functions) |function| {
        if (function.type_arguments.len != 0 or function.policy.c_abi or function.policy.host != null) continue;
        const split = std.mem.lastIndexOf(u8, function.name, "::");
        if (split) |at| if (!std.mem.eql(u8, function.name[0..at], entry)) continue;
        try found.append(a, function.id);
    }
    return found.items;
}

/// Check `path` as a library and build every function of its module, appending a line to `out` when the build refuses
/// what the check accepted.
fn agree(gpa: std.mem.Allocator, path: []const u8, out: *std.ArrayList(u8)) !Outcome {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(a, std.testing.io, path, &report) catch return .check_refused;
    var session = frontend.Session.init(gpa, std.testing.io, entry.root);
    defer session.deinit();
    const checked = entry.checkLibrary(a, &session, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .check_refused,
    };
    const selected = try roots(a, checked.program, entry.name);
    if (selected.len == 0) return .built;
    var refusal: build.Refusal = .{};
    // Every function is lowered as the callee it is in a program (`callee_roots`): internal, with borrowed view parameters.
    const input: build.Input = .{ .program = checked.program, .source = checked.src, .callee_roots = true };
    var module = build.buildRootsCached(a, selected, input, &refusal, null) catch |err| {
        try out.print(gpa, "{s}: lowering refused ({s}): {s}\n", .{ path, @errorName(err), refusal.reason });
        return .disagreed;
    };
    var text: std.ArrayList(u8) = .empty;
    verify_ir.check(a, &module, &.{}, &text) catch |err| {
        try out.print(gpa, "{s}: lowered IR invalid ({s}): {s}\n", .{ path, @errorName(err), text.items });
        return .disagreed;
    };
    var scheduled: own.Refusal = .{};
    const reporting: passes.Reporting = .{ .arena = a, .backing = a, .module = &module, .refusal = &scheduled };
    const result = reporting.runWithScratch(.trusted) catch |err| {
        try out.print(gpa, "{s}: passes refused ({s}) in {s} at {s}\n", .{ path, @errorName(err), scheduled.function, scheduled.operation });
        return .disagreed;
    };
    verify_ir.check(a, &module, result.plans, &text) catch |err| {
        try out.print(gpa, "{s}: optimized IR invalid ({s}): {s}\n", .{ path, @errorName(err), text.items });
        return .disagreed;
    };
    // Rule C, the half of `--verify-facts` that judges copies (lane HC): every copy site of the module that facts
    // verification builds (the passes in `verify` mode) is written. `verify` keeps the facts it checks at run time, so it
    // folds less than `trusted`, and the two modules can differ in their copies: the check runs on a second lowering.
    var verified = build.buildRootsCached(a, selected, input, &refusal, null) catch |err| {
        try out.print(gpa, "{s}: lowering refused ({s}): {s}\n", .{ path, @errorName(err), refusal.reason });
        return .disagreed;
    };
    const verifying: passes.Reporting = .{ .arena = a, .backing = a, .module = &verified, .refusal = &scheduled };
    _ = verifying.runWithScratch(.verify) catch |err| {
        try out.print(gpa, "{s}: verify passes refused ({s}) in {s} at {s}\n", .{ path, @errorName(err), scheduled.function, scheduled.operation });
        return .disagreed;
    };
    verify_ir.writtenCopies(a, &verified, pipeline.locator(&checked.src), true, &text) catch |err| {
        try out.print(gpa, "{s}: hidden copy ({s}): {s}\n", .{ path, @errorName(err), text.items });
        return .disagreed;
    };
    return .built;
}

/// Check and build every file of `part`, appending each disagreement to `out`; the count of each outcome.
fn survey(gpa: std.mem.Allocator, part: Part, out: *std.ArrayList(u8)) !std.EnumArray(Outcome, usize) {
    var counts = std.EnumArray(Outcome, usize).initFill(0);
    var dir = try std.Io.Dir.cwd().openDir(std.testing.io, part.directory, .{ .iterate = true });
    defer dir.close(std.testing.io);
    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |name| gpa.free(name);
        names.deinit(gpa);
    }
    var iterator = dir.iterate();
    while (try iterator.next(std.testing.io)) |item| {
        if (item.kind != .file or !product.isSource(item.name)) continue;
        if (item.name[0] < part.first or item.name[0] >= part.last) continue;
        try names.append(gpa, try std.fs.path.join(gpa, &.{ part.directory, item.name }));
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    for (names.items) |path| counts.getPtr(try agree(gpa, path, out)).* += 1;
    return counts;
}

/// Survey `part` and require every file the check accepts to build, and at least `built` files to build. The disagreements are
/// the expected-empty text the failure prints.
fn expectAgreement(gpa: std.mem.Allocator, part: Part, built: usize) !std.EnumArray(Outcome, usize) {
    var disagreements: std.ArrayList(u8) = .empty;
    defer disagreements.deinit(gpa);
    const counts = try survey(gpa, part, &disagreements);
    try std.testing.expectEqualStrings("", disagreements.items);
    try std.testing.expect(counts.get(.built) >= built);
    return counts;
}

test "check/build corpus: every function of a tests/lang file before m that the check accepts builds" {
    _ = try expectAgreement(std.testing.allocator, .{ .directory = "tests/lang", .last = 'm' }, 140);
}

test "check/build corpus: every function of a tests/lang file from m that the check accepts builds" {
    _ = try expectAgreement(std.testing.allocator, .{ .directory = "tests/lang", .first = 'm' }, 190);
}

test "check/build corpus: every function of a tests/value_semantics or tests/ported file that the check accepts builds" {
    _ = try expectAgreement(std.testing.allocator, .{ .directory = "tests/value_semantics" }, 15);
    _ = try expectAgreement(std.testing.allocator, .{ .directory = "tests/ported" }, 15);
}

test "check/build corpus: the check/build repros either build or are refused by the check" {
    const counts = try expectAgreement(std.testing.allocator, .{ .directory = "test/fixtures/check-build" }, 4);
    // F-PB-2 (E_SLICE_ESCAPES), defect 4 (`from_view_source.selka`, E_BORROW_SOURCE), its generic case
    // (`generic_from_view_source.selka`) and a list source of another element type (`unlendable_list_source.selka`, lane HC) are
    // refused by the check; F-PB-1, F-PB-3, a source that cannot lend beside one that can (`lend_beside.selka`) and options
    // given to tasks (`task_option_argument.selka`, lane OC) build.
    try std.testing.expectEqual(@as(usize, 4), counts.get(.check_refused));
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

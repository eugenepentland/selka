//! The `test-exec` and `test-report` kinds (spec section 13) and the engine features the runner needs: the keyed
//! environment as a read, `Engine.answer`'s origin, and verify mode's tolerance of a kind that cannot recompute.
const std = @import("std");
const fixture_rules = @import("fixture_test.zig");
const script = @import("kinds/script.zig");
const kinds = @import("kinds.zig");
const test_exec = @import("kinds/test_exec.zig");
const test_report = @import("kinds/test_report.zig");
const engine_rules = @import("engine.zig");
const context = @import("context.zig");
const Fixture = fixture_rules.Fixture;

const second = std.time.ns_per_s;
const one_file: script.Graph = .{ .nodes = &.{fixture_rules.fileNode("/src/a.txt", .concat)} };

/// What a test tells the stand-in for the runner: whether it has an answer, and how often it was asked.
const Stub = struct { answers: bool = true, calls: u32 = 0 };

fn execAnswer(raw: *anyopaque, _: []const u8) ?[]const u8 {
    const stub: *Stub = @ptrCast(@alignCast(raw));
    stub.calls += 1;
    return if (stub.answers) test_exec.passed else null;
}

fn reportAnswer(raw: *anyopaque, _: []const u8) ?test_report.Answer {
    const stub: *Stub = @ptrCast(@alignCast(raw));
    stub.calls += 1;
    return if (stub.answers) .{ .files = &.{"/src/a.txt"}, .payload = "a\t-\n" } else null;
}

fn aged(gpa: std.mem.Allocator) fixture_rules.Failure!*Fixture {
    const fx = try Fixture.create(gpa, one_file);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", "alpha");
    fx.files.advance(second);
    return fx;
}

/// A kind that reads the keyed environment, to test the read itself: its payload is how many variables are keyed.
fn environmentRun(ctx: *context.Context, _: []const u8) context.Error![]const u8 {
    const names = try ctx.environment();
    return std.fmt.allocPrint(ctx.arena, "{d}", .{names.len});
}

test "shadow kinds: the keyed environment is one read, changed by a keyed variable and not by a placement one" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    const kind: context.Kind = .{ .name = "environment-probe", .identity = @splat(9), .run = environmentRun };
    try fx.files.setVariable("KEYED", "1");
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.recomputed, (try fx.runner.answer(&kind, "")).origin);
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.served, (try fx.runner.answer(&kind, "")).origin);
    try fx.files.setVariable("PLACE_where", "elsewhere");
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.served, (try fx.runner.answer(&kind, "")).origin);
    try fx.files.setVariable("KEYED", "2");
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.recomputed, (try fx.runner.answer(&kind, "")).origin);
    try fx.files.setVariable("ANOTHER", "1");
    try fx.restartWith(.{}, &.{&kind});
    const added = try fx.runner.answer(&kind, "");
    try std.testing.expectEqual(engine_rules.Origin.recomputed, added.origin);
    try std.testing.expectEqualStrings("2", try added.result.payload());
}

test "shadow kinds: test-exec serves a recorded pass to the argument that earned it, and reads nothing" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    var stub: Stub = .{};
    const source: test_exec.Source = .{ .context = &stub, .answer = execAnswer };
    var kind = kinds.test_exec;
    kind.data = &source;
    try fx.restartWith(.{}, &.{&kind});
    const first = try fx.runner.answer(&kind, "p-program-inputs-environment-name");
    try std.testing.expectEqual(engine_rules.Origin.recomputed, first.origin);
    try std.testing.expectEqualStrings(test_exec.passed, try first.result.payload());
    // Another environment, program or settings is another argument, hence another record; the same one is served.
    try fx.files.setVariable("KEYED", "2");
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.served, (try fx.runner.answer(&kind, "p-program-inputs-environment-name")).origin);
    try std.testing.expectEqual(engine_rules.Origin.recomputed, (try fx.runner.answer(&kind, "p-program-inputs-other-environment-name")).origin);
    try std.testing.expectEqual(@as(u32, 2), stub.calls);
}

test "shadow kinds: an answer the runner does not have fails the query and stores nothing" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    var stub: Stub = .{ .answers = false };
    const source: test_exec.Source = .{ .context = &stub, .answer = execAnswer };
    var kind = kinds.test_exec;
    kind.data = &source;
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectError(error.Failed, fx.runner.answer(&kind, "t"));
    stub.answers = true;
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.recomputed, (try fx.runner.answer(&kind, "t")).origin);
    try std.testing.expectEqual(engine_rules.Origin.memo, (try fx.runner.answer(&kind, "t")).origin);
}

test "shadow kinds: verify mode counts a served query it cannot recompute and does not fail it" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    var stub: Stub = .{};
    const source: test_exec.Source = .{ .context = &stub, .answer = execAnswer };
    var kind = kinds.test_exec;
    kind.data = &source;
    try fx.restartWith(.{}, &.{&kind});
    _ = try fx.runner.answer(&kind, "t");
    stub.answers = false;
    try fx.restartWith(.{ .verify_every = 1 }, &.{&kind});
    const served = try fx.runner.answer(&kind, "t");
    try std.testing.expectEqual(engine_rules.Origin.served, served.origin);
    const numbers = fx.runner.snapshot(&kind).?;
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.unverifiable));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.verified));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.verify_mismatches));
}

test "test-report reads the files of the report, so a changed file is recomputed and an unchanged one is served" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    var stub: Stub = .{};
    const source: test_report.Source = .{ .context = &stub, .answer = reportAnswer };
    var kind = kinds.test_report;
    kind.data = &source;
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.recomputed, (try fx.runner.answer(&kind, "plan")).origin);
    try fx.restartWith(.{}, &.{&kind});
    const again = try fx.runner.answer(&kind, "plan");
    try std.testing.expectEqual(engine_rules.Origin.served, again.origin);
    try std.testing.expectEqualStrings("a\t-\n", try again.result.payload());
    try fx.files.replace("/src/a.txt", "beta");
    fx.files.advance(second);
    try fx.restartWith(.{}, &.{&kind});
    try std.testing.expectEqual(engine_rules.Origin.recomputed, (try fx.runner.answer(&kind, "plan")).origin);
    try std.testing.expectEqual(@as(u32, 2), stub.calls);
}

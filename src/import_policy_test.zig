const std = @import("std");
const t = std.testing;
const policy = @import("import_policy.zig");
const graph = @import("project.zig");
const rules =
    \\{"version":1,"default_action":"deny","rules":[
    \\{"from":"main","to":"*","action":"allow","reason":"entry may assemble components"},
    \\{"from":"core.*","to":"io.*","action":"deny","reason":"core must not import I/O adapters"},
    \\{"from":"other.*","to":"*","action":"allow","reason":"another entry graph"}]}
;
fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
    const bytes = fixtureBytes(path) orelse return error.NotFound;
    if (bytes.len > limit) return error.TooLarge;
    return allocator.dupe(u8, bytes);
}
fn scenario(allocator: std.mem.Allocator) !void {
    var config = try policy.Policy.parse(allocator, rules);
    defer config.deinit();
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = read }, "main", .{});
    var report = try policy.evaluate(allocator, &project, config);
    defer report.deinit();
    try t.expectEqual(@as(usize, 1), report.denied);
    try t.expectEqualSlices(usize, &.{ 2, 1, 0 }, report.rule_hits);
    try t.expect(project.problem == null);
    const text = try policy.render(allocator, report, &project, config);
    defer allocator.free(text);
    for ([_][]const u8{
        "scope=reachable-import-graph; edges=3; denied=1",
        "core/service.my:1:",
        "core.service -> io.fs: deny; rule=2",
        "rule 3: matched-edges=0",
        "config-sha256=",
    }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
    const again = try policy.render(allocator, report, &project, config);
    defer allocator.free(again);
    try t.expectEqualStrings(text, again);
}
test "import policy evaluates resolved direct edges without mutating language state under allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "policy patterns respect namespace segment boundaries" {
    try t.expect(policy.matches("core.*", "core.service"));
    try t.expect(policy.matches("core.*", "core.service.more"));
    try t.expect(!policy.matches("core.*", "core"));
    try t.expect(!policy.matches("core.*", "coreish.service"));
    try t.expect(!policy.matches("core", "core.service"));
    try t.expect(policy.matches("*", "core"));
    for ([_][]const u8{ "", "**", "core*", "*.core", "core..*", "../io", "core.*.impl" }) |pattern| try t.expect(!policy.validPattern(pattern));
}
test "policy parser rejects unknown fields duplicate keys versions invalid patterns and unexplained rules" {
    for ([_][]const u8{
        "{\"version\":2,\"default_action\":\"allow\",\"rules\":[]}",
        "{\"version\":1,\"default_action\":\"allow\",\"rules\":[],\"typo\":true}",
        "{\"version\":1,\"version\":1,\"default_action\":\"allow\",\"rules\":[]}",
        "{\"version\":1,\"rules\":[]}",
        "{\"version\":1,\"default_action\":\"allow\",\"rules\":[{\"from\":\"a*\",\"to\":\"*\",\"action\":\"deny\",\"reason\":\"bad glob\"}]}",
        "{\"version\":1,\"default_action\":\"allow\",\"rules\":[{\"from\":\"a\",\"to\":\"*\",\"action\":\"deny\",\"reason\":\"\"}]}",
        "{\"version\":1,\"default_action\":\"allow\",\"rules\":[{\"from\":\"a\",\"to\":\"*\",\"action\":\"deny\",\"reason\":\"line\\nbreak\"}]}",
    }, [_]anyerror{
        error.UnsupportedPolicyVersion, error.UnknownField,         error.DuplicateField,
        error.MissingField,             error.InvalidPolicyPattern, error.InvalidPolicyReason,
        error.InvalidPolicyReason,
    }) |text, expected| try t.expectError(expected, policy.Policy.parse(t.allocator, text));
}
test "first matching policy rule wins and defaults apply to remaining edges" {
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = read }, "main", .{});
    var config = try policy.Policy.parse(t.allocator,
        \\{"version":1,"default_action":"deny","rules":[{"from":"*","to":"*","action":"allow","reason":"broad allowance"},{"from":"core.*","to":"io.*","action":"deny","reason":"shadowed rule"}]}
    );
    defer config.deinit();
    var report = try policy.evaluate(t.allocator, &project, config);
    defer report.deinit();
    try t.expectEqual(@as(usize, 0), report.denied);
    try t.expectEqualSlices(usize, &.{ 3, 0 }, report.rule_hits);
    var fallback = try policy.Policy.parse(t.allocator, "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}");
    defer fallback.deinit();
    var denied = try policy.evaluate(t.allocator, &project, fallback);
    defer denied.deinit();
    try t.expectEqual(@as(usize, 3), denied.denied);
    for (denied.decisions) |decision| try t.expect(decision.rule == null);
    var empty = graph.Project.init(t.allocator);
    defer empty.deinit();
    try t.expectError(error.IncompleteProject, policy.evaluate(t.allocator, &empty, fallback));
}

test "policy bounds and duplicate rule validation are explicit" {
    try t.expectError(error.DuplicatePolicyRule, policy.Policy.parse(t.allocator,
        \\{"version":1,"default_action":"allow","rules":[{"from":"a","to":"b","action":"allow","reason":"one"},{"from":"a","to":"b","action":"deny","reason":"two"}]}
    ));
    const oversized = try t.allocator.alloc(u8, 1024 * 1024 + 1);
    defer t.allocator.free(oversized);
    try t.expectError(error.PolicyTooLarge, policy.Policy.parse(t.allocator, oversized));
    var output: std.Io.Writer.Allocating = .init(t.allocator);
    defer output.deinit();
    try output.writer.writeAll("{\"version\":1,\"default_action\":\"allow\",\"rules\":[");
    for (0..1025) |i| {
        if (i != 0) try output.writer.writeByte(',');
        try output.writer.print("{{\"from\":\"m{d}\",\"to\":\"*\",\"action\":\"allow\",\"reason\":\"bounded\"}}", .{i});
    }
    try output.writer.writeAll("]}");
    try t.expectError(error.TooManyPolicyRules, policy.Policy.parse(t.allocator, output.written()));
}

fn fixtureBytes(path: []const u8) ?[]const u8 {
    const files = std.StaticStringMap([]const u8).initComptime(.{
        .{ "main.my", "module main; import core.service; import io.fs;" },
        .{ "core/service.my", "module core.service; import io.fs;" },
        .{ "io/fs.my", "module io.fs;" },
    });
    return files.get(path);
}

test "policy fixture reader rejects missing input instead of fabricating source" {
    try t.expectError(error.NotFound, read(null, t.allocator, "missing.my", 4096));
}

test "policy parsing rejects invalid actions and byte and rule budgets" {
    try t.expectError(error.InvalidEnumTag, policy.Policy.parse(t.allocator, "{\"version\":1,\"default_action\":\"unknown\",\"rules\":[]}"));
    const oversized = try t.allocator.alloc(u8, 1024 * 1024 + 1);
    defer t.allocator.free(oversized);
    @memset(oversized, ' ');
    try t.expectError(error.PolicyTooLarge, policy.Policy.parse(t.allocator, oversized));
    const entries = try t.allocator.alloc(policy.Rule, 1025);
    defer t.allocator.free(entries);
    @memset(entries, .{ .from = "*", .to = "*", .action = .allow, .reason = "test" });
    const bytes = try std.json.Stringify.valueAlloc(t.allocator, policy.Document{ .version = 1, .default_action = .deny, .rules = entries }, .{});
    defer t.allocator.free(bytes);
    try t.expectError(error.TooManyPolicyRules, policy.Policy.parse(t.allocator, bytes));
}

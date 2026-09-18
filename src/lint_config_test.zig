//! Tests for the strict `lint` object parser and its profile resolution.
const std = @import("std");
const t = std.testing;
const lint_config = @import("lint_config.zig");
const project_config = @import("project_config.zig");

fn writeTmp(dir: *std.testing.TmpDir, path: []const u8, body: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try dir.dir.createDirPath(t.io, parent);
    try dir.dir.writeFile(t.io, .{ .sub_path = path, .data = body });
}

fn loadTmp(dir: *std.testing.TmpDir, path: []const u8, failure: *project_config.Failure) !project_config.Config {
    const absolute = try dir.dir.realPathFileAlloc(t.io, path, t.allocator);
    defer t.allocator.free(absolute);
    return project_config.load(t.allocator, t.io, absolute, failure);
}

const rich_body =
    \\{"version":2,"lint":{"profile":"strict","on_build":"block","warnings":"deny",
    \\"block":["untested-export"],"ratchet":["function-length"],"report":["dead-export"],
    \\"rules":{"function-length":{"max":80,"hard_max":200,"recover_pct":20},
    \\"test-coverage":{"exempt":[{"name":"cli.usage","reason":"exercised by the CLI"}],
    \\"modules":["*_integration"]}}}}
;

// spec: LINT-2
test "lint config parseObject resolves the profile shorthands and per-rule settings" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    try writeTmp(&temp, "config.json", rich_body);
    var failure: project_config.Failure = .{};
    var loaded = try loadTmp(&temp, "config.json", &failure);
    defer loaded.deinit();
    try t.expect(loaded.document.lint);
    var lint_failure: lint_config.Failure = .{};
    var config = try lint_config.parseConfig(t.allocator, loaded.bytes, &lint_failure);
    defer config.deinit(t.allocator);
    try t.expectEqual(lint_config.Profile.strict, config.profile);
    try t.expectEqual(lint_config.OnBuild.block, config.on_build);
    try t.expectEqual(lint_config.Warnings.deny, config.warnings);
    try t.expectEqual(lint_config.Mode.block, config.modeFor("untested-export", .report));
    try t.expectEqual(lint_config.Mode.ratchet, config.modeFor("function-length", .off));
    try t.expectEqual(lint_config.Mode.report, config.modeFor("dead-export", .off));
    try t.expectEqual(lint_config.Mode.off, config.modeFor("naming", .off));
    const setting = config.setting("function-length").?;
    try t.expectEqual(@as(?usize, 80), setting.max);
    try t.expectEqual(@as(?usize, 200), setting.hard_max);
    try t.expectEqual(@as(?usize, 20), setting.recover_pct);
    const exemption = config.setting("test-coverage").?.exempt[0];
    try t.expectEqualStrings("cli.usage", exemption.name);
    try t.expectEqualStrings("exercised by the CLI", exemption.reason);
    const modules = config.setting("test-coverage").?.modules;
    try t.expectEqual(@as(usize, 1), modules.len);
    try t.expectEqualStrings("*_integration", modules[0]);
    var identity: [64]u8 = undefined;
    try t.expect(loaded.cacheIdentity(&identity));
}

// spec-case: LINT-2
test "lint config parseShorthand parseRules parseRuleSetting parseExemptions and parseStringArray reject bad shapes" {
    const cases = [_]struct { body: []const u8, want: anyerror }{
        .{ .body = "{\"version\":2,\"lint\":{\"profile\":\"loose\"}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"warnings\":\"block\"}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"block\":\"untested-export\"}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"block\":[\"a\"],\"block\":[\"b\"]}}", .want = error.DuplicateField },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":[]}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":1}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"max\":0}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"max\":\"7\"}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"unknown\":1}}}}", .want = error.UnknownField },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"exempt\":{\"name\":\"a\",\"reason\":\"b\"}}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"exempt\":[{\"name\":\"a\"}]}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"exempt\":[{\"name\":\"a\",\"reason\":\"\"}]}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"exempt\":[{\"name\":\"a\",\"reason\":\"b\",\"extra\":\"x\"}]}}}}", .want = error.UnknownField },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"exempt\":[{\"name\":\"a\",\"reason\":\"b\",\"extra\":1}]}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"modules\":[\"\"]}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"rules\":{\"x\":{\"modules\":7}}}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":\"agent\"}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"profile\":\"agent\"},\"lint\":{}}", .want = error.DuplicateField },
    };
    inline for (cases) |item| {
        var failure: lint_config.Failure = .{};
        try t.expectError(item.want, lint_config.parseConfig(t.allocator, item.body, &failure));
        try t.expect(failure.detail.len != 0);
    }
}

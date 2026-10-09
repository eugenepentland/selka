//! Unit tests for the import-direction policy evaluator and the `selka.json`
//! project configuration that makes the policy required for ordinary commands.
const source_names = @import("source_names.zig");
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
        "core/service.selka:1:",
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

test "one edge's policy decision is the evaluator's first matching rule or the default" {
    var config = try policy.Policy.parse(t.allocator,
        \\{"version":1,"default_action":"allow","rules":[{"from":"core.*","to":"app.*","action":"deny","reason":"layering"},{"from":"core.*","to":"*","action":"allow","reason":"core may use anything else"}]}
    );
    defer config.deinit();
    try t.expect(policy.denies(config, "core.model", "app.view"));
    try t.expect(!policy.denies(config, "core.model", "core.util"));
    try t.expect(!policy.denies(config, "app.view", "core.model"));
    try t.expectEqual(@as(?usize, 1), policy.ruleFor(config, "core.model", "hex"));
    try t.expectEqual(@as(?usize, null), policy.ruleFor(config, "main", "hex"));
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
        .{ source_names.entry, "import core.service\nimport io.fs\n" },
        .{ "core/service.selka", "import io.fs\n" },
        .{ "io/fs.selka", "" },
    });
    return files.get(path);
}

test "policy fixture reader rejects missing input instead of fabricating source" {
    try t.expectError(error.NotFound, read(null, t.allocator, "missing.selka", 4096));
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

const project_config = @import("compiler.zig").project_config;
const valid_policy = "{\"version\":1,\"default_action\":\"allow\",\"rules\":[]}";

fn writeTmp(dir: *std.testing.TmpDir, path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try dir.dir.createDirPath(t.io, parent);
    try dir.dir.writeFile(t.io, .{ .sub_path = path, .data = data });
}

fn loadTmp(dir: *std.testing.TmpDir, path: []const u8, failure: *project_config.Failure) !project_config.Config {
    const absolute = try dir.dir.realPathFileAlloc(t.io, path, t.allocator);
    defer t.allocator.free(absolute);
    return project_config.load(t.allocator, t.io, absolute, failure);
}

// spec: REQUIRED-PROJECT-IMPORT-POLICY-1
test "project config discovery walks up from the entry and resolves policy beside the winning config" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    try writeTmp(&temp, "selka.json", "{\"version\":1}");
    try writeTmp(&temp, "nested/policy.json", valid_policy);
    try writeTmp(&temp, "nested/selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeTmp(&temp, "nested/deeper/entry.selka", "");

    const entry = try temp.dir.realPathFileAlloc(t.io, "nested/deeper/entry.selka", t.allocator);
    defer t.allocator.free(entry);
    const found = (try project_config.discover(t.allocator, t.io, entry)).?;
    defer t.allocator.free(found);
    try t.expect(std.mem.endsWith(u8, found, "nested/selka.json"));
    try t.expect(!std.mem.endsWith(u8, found, "deeper/selka.json"));

    var failure: project_config.Failure = .{};
    var loaded = try project_config.load(t.allocator, t.io, found, &failure);
    defer loaded.deinit();
    try t.expectEqual(@as(u32, 1), loaded.document.version);
    try t.expect(loaded.hasPolicy());
    const policy_path = loaded.policy.?.path;
    try t.expect(std.mem.endsWith(u8, policy_path, "nested/policy.json"));
    try t.expect(!loaded.policy.?.absolute);

    var first_identity: [64]u8 = undefined;
    try t.expect(loaded.cacheIdentity(&first_identity));
    try writeTmp(&temp, "nested/policy.json", "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}");
    var changed = try project_config.load(t.allocator, t.io, found, &failure);
    defer changed.deinit();
    var second_identity: [64]u8 = undefined;
    try t.expect(changed.cacheIdentity(&second_identity));
    try t.expect(!std.mem.eql(u8, &first_identity, &second_identity));
    const receipt = try changed.receipt(t.allocator);
    defer {
        t.allocator.free(receipt.config_sha256);
        if (receipt.policy_sha256) |value| t.allocator.free(value);
    }
    try t.expectEqual(@as(usize, 64), receipt.config_sha256.len);
    try t.expectEqual(@as(usize, 64), receipt.policy_sha256.?.len);
}

// spec-case: PROJ-6
test "selka json budgets override the project loading limits" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    var failure: project_config.Failure = .{};
    try writeTmp(&temp, "plain.json", "{\"version\":1}");
    var plain = try loadTmp(&temp, "plain.json", &failure);
    defer plain.deinit();
    // An absent budgets object leaves every limit at the project default.
    try t.expectEqual(@as(?usize, null), plain.document.budgets.max_modules);
    try t.expectEqual(@as(?usize, null), plain.document.budgets.max_imports);
    try writeTmp(&temp, "budgeted.json", "{\"version\":1,\"budgets\":{\"max_modules\":9000,\"max_imports\":20000,\"max_file_bytes\":8388608,\"max_total_bytes\":67108864}}");
    var budgeted = try loadTmp(&temp, "budgeted.json", &failure);
    defer budgeted.deinit();
    try t.expectEqual(@as(?usize, 9000), budgeted.document.budgets.max_modules);
    try t.expectEqual(@as(?usize, 20000), budgeted.document.budgets.max_imports);
    try t.expectEqual(@as(?usize, 8 * 1024 * 1024), budgeted.document.budgets.max_file_bytes);
    try t.expectEqual(@as(?usize, 64 * 1024 * 1024), budgeted.document.budgets.max_total_bytes);
    try writeTmp(&temp, "zero.json", "{\"version\":1,\"budgets\":{\"max_modules\":0}}");
    try t.expectError(error.InvalidBudget, loadTmp(&temp, "zero.json", &failure));
    try writeTmp(&temp, "unknown.json", "{\"version\":1,\"budgets\":{\"max_names\":1}}");
    try t.expectError(error.UnknownField, loadTmp(&temp, "unknown.json", &failure));
    try writeTmp(&temp, "duplicate.json", "{\"version\":1,\"budgets\":{\"max_modules\":1,\"max_modules\":2}}");
    try t.expectError(error.DuplicateField, loadTmp(&temp, "duplicate.json", &failure));
}

// spec-case: PROJECT-LIMITS-1
test "selka json limits carry per-command execution defaults" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    var failure: project_config.Failure = .{};
    try writeTmp(&temp, "plain.json", "{\"version\":1}");
    var plain = try loadTmp(&temp, "plain.json", &failure);
    defer plain.deinit();
    try t.expectEqual(@as(?u64, null), plain.document.limits.run.max_frames);
    try t.expectEqual(@as(?u64, null), plain.document.limits.tests.max_memory);
    try writeTmp(&temp, "limited.json", "{\"version\":1,\"limits\":{\"run\":{\"max_steps\":500,\"max_frames\":2000,\"max_memory\":\"2G\"},\"test\":{\"max_frames\":30000,\"max_memory\":1048576}}}");
    var limited = try loadTmp(&temp, "limited.json", &failure);
    defer limited.deinit();
    try t.expectEqual(@as(?u64, 500), limited.document.limits.run.max_steps);
    try t.expectEqual(@as(?u64, 2000), limited.document.limits.run.max_frames);
    try t.expectEqual(@as(?u64, 2 << 30), limited.document.limits.run.max_memory);
    try t.expectEqual(@as(?u64, null), limited.document.limits.tests.max_steps);
    try t.expectEqual(@as(?u64, 30000), limited.document.limits.tests.max_frames);
    try t.expectEqual(@as(?u64, 1048576), limited.document.limits.tests.max_memory);
    const rejected = [_]struct { body: []const u8, want: anyerror }{
        .{ .body = "{\"version\":1,\"limits\":[]}", .want = error.InvalidLimits },
        .{ .body = "{\"version\":1,\"limits\":{\"run\":1}}", .want = error.InvalidLimits },
        .{ .body = "{\"version\":1,\"limits\":{\"run\":{\"max_frames\":0}}}", .want = error.InvalidLimits },
        .{ .body = "{\"version\":1,\"limits\":{\"run\":{\"max_steps\":\"many\"}}}", .want = error.InvalidLimits },
        .{ .body = "{\"version\":1,\"limits\":{\"test\":{\"max_frames\":4294967296}}}", .want = error.InvalidLimits },
        .{ .body = "{\"version\":1,\"limits\":{\"test\":{\"max_memory\":\"12x\"}}}", .want = error.InvalidLimits },
        .{ .body = "{\"version\":1,\"limits\":{\"build\":{}}}", .want = error.UnknownField },
        .{ .body = "{\"version\":1,\"limits\":{\"run\":{\"max_calls\":1}}}", .want = error.UnknownField },
        .{ .body = "{\"version\":1,\"limits\":{\"run\":{},\"run\":{}}}", .want = error.DuplicateField },
        .{ .body = "{\"version\":1,\"limits\":{\"run\":{\"max_frames\":1,\"max_frames\":2}}}", .want = error.DuplicateField },
        .{ .body = "{\"version\":1,\"limits\":{},\"limits\":{}}", .want = error.DuplicateField },
    };
    for (rejected) |case| {
        try writeTmp(&temp, "bad.json", case.body);
        try t.expectError(case.want, loadTmp(&temp, "bad.json", &failure));
    }
}

// spec-case: API-FILE-3
test "selka json interface_files is an optional boolean" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    var failure: project_config.Failure = .{};
    try writeTmp(&temp, "plain.json", "{\"version\":1}");
    var plain = try loadTmp(&temp, "plain.json", &failure);
    defer plain.deinit();
    try t.expect(!plain.document.interface_files);
    try writeTmp(&temp, "enabled.json", "{\"version\":1,\"interface_files\":true}");
    var enabled = try loadTmp(&temp, "enabled.json", &failure);
    defer enabled.deinit();
    try t.expect(enabled.document.interface_files);
    try writeTmp(&temp, "text.json", "{\"version\":1,\"interface_files\":\"yes\"}");
    try t.expectError(error.InvalidInterfaceFiles, loadTmp(&temp, "text.json", &failure));
    try t.expectEqualStrings("interface_files must be true or false", failure.detail);
    try writeTmp(&temp, "twice.json", "{\"version\":1,\"interface_files\":true,\"interface_files\":false}");
    try t.expectError(error.DuplicateField, loadTmp(&temp, "twice.json", &failure));
}

// spec: VALUE-SEMANTICS-1
test "selka json value_semantics is an optional boolean" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    var failure: project_config.Failure = .{};
    try writeTmp(&temp, "plain.json", "{\"version\":1}");
    var plain = try loadTmp(&temp, "plain.json", &failure);
    defer plain.deinit();
    try t.expect(plain.document.value_semantics);
    try writeTmp(&temp, "enabled.json", "{\"version\":1,\"value_semantics\":true}");
    var enabled = try loadTmp(&temp, "enabled.json", &failure);
    defer enabled.deinit();
    try t.expect(enabled.document.value_semantics);
    try writeTmp(&temp, "disabled.json", "{\"version\":1,\"value_semantics\":false}");
    var disabled = try loadTmp(&temp, "disabled.json", &failure);
    defer disabled.deinit();
    try t.expect(!disabled.document.value_semantics);
    try writeTmp(&temp, "text.json", "{\"version\":1,\"value_semantics\":1}");
    try t.expectError(error.InvalidValueSemantics, loadTmp(&temp, "text.json", &failure));
    try t.expectEqualStrings("value_semantics must be true or false", failure.detail);
    try writeTmp(&temp, "twice.json", "{\"version\":1,\"value_semantics\":true,\"value_semantics\":false}");
    try t.expectError(error.DuplicateField, loadTmp(&temp, "twice.json", &failure));
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "project config rejects unknown duplicate malformed and unsupported shapes" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const cases = [_]struct { body: []const u8, want: anyerror }{
        .{ .body = "{", .want = error.InvalidJson },
        .{ .body = "{\"version\":1,\"version\":1}", .want = error.DuplicateField },
        .{ .body = "{\"version\":1,\"extra\":true}", .want = error.UnknownField },
        .{ .body = "{\"version\":\"1\"}", .want = error.InvalidVersion },
        .{ .body = "{\"version\":3}", .want = error.UnsupportedVersion },
        .{ .body = "{\"version\":1,\"lint\":{\"profile\":\"agent\"}}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":7}", .want = error.InvalidLint },
        .{ .body = "{\"version\":2,\"lint\":{\"on_build\":\"block\"},\"lint\":{\"profile\":\"agent\"}}", .want = error.DuplicateField },
        .{ .body = "{}", .want = error.MissingVersion },
        .{ .body = "{\"version\":1,\"import_policy\":7}", .want = error.InvalidImportPolicy },
        .{ .body = "{\"version\":1,\"import_policy\":\"\"}", .want = error.InvalidImportPolicy },
    };
    for (cases, 0..) |item, index| {
        const name = try std.fmt.allocPrint(t.allocator, "case{d}.json", .{index});
        defer t.allocator.free(name);
        try writeTmp(&temp, name, item.body);
        const path = try temp.dir.realPathFileAlloc(t.io, name, t.allocator);
        defer t.allocator.free(path);
        var failure: project_config.Failure = .{};
        try t.expectError(item.want, project_config.load(t.allocator, t.io, path, &failure));
        try t.expect(failure.path.len != 0);
        try t.expectEqual(@as(u64, 1), failure.location.line);
    }
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "project config reports missing oversized and unreadable files" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    var failure: project_config.Failure = .{};
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const missing = try std.fs.path.join(t.allocator, &.{ root, "absent" });
    defer t.allocator.free(missing);
    try t.expectError(error.MissingConfig, project_config.load(t.allocator, t.io, missing, &failure));

    try temp.dir.createDir(t.io, "as-directory", .default_dir);
    const directory_path = try temp.dir.realPathFileAlloc(t.io, "as-directory", t.allocator);
    defer t.allocator.free(directory_path);
    try t.expectError(error.ReadFailed, project_config.load(t.allocator, t.io, directory_path, &failure));

    const huge = try t.allocator.alloc(u8, project_config.max_config_bytes + 1);
    defer t.allocator.free(huge);
    @memset(huge, ' ');
    try writeTmp(&temp, "huge.json", huge);
    try t.expectError(error.ConfigTooLarge, loadTmp(&temp, "huge.json", &failure));

    try writeTmp(&temp, "policy.json", valid_policy);
    try writeTmp(&temp, "config.json", "{\"version\":1,\"import_policy\":\"missing-policy.json\"}");
    try t.expectError(error.MissingImportPolicy, loadTmp(&temp, "config.json", &failure));

    try writeTmp(&temp, "big-policy.json", huge);
    try writeTmp(&temp, "config-big.json", "{\"version\":1,\"import_policy\":\"big-policy.json\"}");
    try t.expectError(error.PolicyTooLarge, loadTmp(&temp, "config-big.json", &failure));
}

//! The environment identity contract against its golden fixture
//! (`test/fixtures/environment-identity`, embedded by `build.zig`), which
//! `scripts/verification_environment_test.py` checks with the Python reader too.
const std = @import("std");
const identity = @import("environment_identity.zig");

const environment_text = @embedFile("environment-identity/environment.txt");
const classification_text = @embedFile("environment-identity/classification.txt");
const tools_text = @embedFile("environment-identity/tools.txt");
const guest_digest_text = @embedFile("environment-identity/digest-guest.txt");
const host_digest_text = @embedFile("environment-identity/digest-host.txt");

/// The fixture's `NAME=VALUE` lines, split at the first `=`, into `buffer`.
fn fixtureVariables(buffer: []identity.Variable) []identity.Variable {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, environment_text, "\n"), '\n');
    while (lines.next()) |line| {
        const name, const value = std.mem.cutScalar(u8, line, '=').?;
        buffer[count] = .{ .name = name, .value = value };
        count += 1;
    }
    return buffer[0..count];
}

/// The fixture's `NAME DIGEST` tool lines into `buffer`.
fn fixtureTools(buffer: []identity.Tool) []identity.Tool {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, tools_text, "\n"), '\n');
    while (lines.next()) |line| {
        const name, const digest = std.mem.cutScalar(u8, line, ' ').?;
        buffer[count] = .{ .name = name, .digest = digest };
        count += 1;
    }
    return buffer[0..count];
}

/// The first `NAME CLASS` line whose class `classify` disagrees with, or "".
fn firstMisclassified() []const u8 {
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, classification_text, "\n"), '\n');
    while (lines.next()) |line| {
        const name, const class = std.mem.cutScalar(u8, line, ' ').?;
        if (!std.mem.eql(u8, @tagName(identity.classify(name)), class)) return line;
    }
    return "";
}

/// How many fixture lines carry `class`.
fn classCount(class: identity.Class) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, classification_text, "\n"), '\n');
    while (lines.next()) |line| {
        if (std.mem.endsWith(u8, line, @tagName(class))) count += 1;
    }
    return count;
}

/// The `scope` digest of `variables` with `name` set to `value` (added if absent).
fn digestWith(scope: identity.Scope, variables: []identity.Variable, tools: []identity.Tool, name: []const u8, value: []const u8) [64]u8 {
    var copy: [512]identity.Variable = undefined;
    @memcpy(copy[0..variables.len], variables);
    for (copy[0..variables.len]) |*variable| {
        if (!std.mem.eql(u8, variable.name, name)) continue;
        variable.value = value;
        return identity.digest(scope, copy[0..variables.len], tools);
    }
    copy[variables.len] = .{ .name = name, .value = value };
    return identity.digest(scope, copy[0 .. variables.len + 1], tools);
}

// spec: ENV-IDENTITY-1
test "environment identity classifies all 200-plus fixture variables as the golden file says" {
    try std.testing.expectEqualStrings("", firstMisclassified());
    var buffer: [512]identity.Variable = undefined;
    try std.testing.expect(fixtureVariables(&buffer).len >= 200);
    try std.testing.expect(classCount(.keyed) > 0);
    try std.testing.expect(classCount(.host) > 0);
    try std.testing.expect(classCount(.placement) > 0);
    try std.testing.expect(classCount(.dropped) > 0);
}

// spec-case: ENV-IDENTITY-1
test "environment identity precedence: exact names, then the longest prefix, else dropped" {
    try std.testing.expectEqual(.keyed, identity.classify("MYLANG_MEMORY_LIMIT"));
    try std.testing.expectEqual(.placement, identity.classify("MYLANG_JOBS"));
    try std.testing.expectEqual(.keyed, identity.classify("MYLANG_JOBSX"));
    try std.testing.expectEqual(.placement, identity.classify("MYL_CORE_PARENT_TOOL_TICKET"));
    try std.testing.expectEqual(.placement, identity.classify("MYLANG_ADMISSION_DIR"));
    try std.testing.expectEqual(.keyed, identity.classify("MYLANG_ADMISSIONS"));
    try std.testing.expectEqual(.keyed, identity.classify("MYLANG_ZIG"));
    try std.testing.expectEqual(.keyed, identity.classify("ZIG"));
    try std.testing.expectEqual(.placement, identity.classify("ZIG_LOCAL_CACHE_DIR"));
    try std.testing.expectEqual(.dropped, identity.classify("ZIG_VERBOSE_LINK"));
    try std.testing.expectEqual(.keyed, identity.classify("LD_PRELOAD"));
    try std.testing.expectEqual(.host, identity.classify("LC_ALL"));
    try std.testing.expectEqual(.host, identity.classify("PYTHONPATH"));
    try std.testing.expectEqual(.host, identity.classify("LANG"));
    try std.testing.expectEqual(.keyed, identity.classify("ZERO_AR_DATE"));
    try std.testing.expect(!identity.keyed("TZ") and identity.hostKeyed("TZ") and identity.passedThrough("TZ"));
    try std.testing.expect(identity.hostKeyed("MYLANG_OPTIONS") and !identity.hostKeyed("TMPDIR"));
    try std.testing.expectEqual(.dropped, identity.classify("CODEX_THREAD_ID"));
    try std.testing.expectEqual(.dropped, identity.classify("TERM"));
    try std.testing.expectEqual(.dropped, identity.classify("PWD"));
    try std.testing.expectEqual(.dropped, identity.classify("mylang_jobs"));
    try std.testing.expectEqual(.dropped, identity.classify(""));
    try std.testing.expect(identity.passedThrough("TMPDIR") and !identity.keyed("TMPDIR"));
    try std.testing.expect(identity.passedThrough("MYL_CORE_LEAKCHECK") and identity.keyed("MYL_CORE_LEAKCHECK"));
    try std.testing.expect(!identity.passedThrough("SSH_AUTH_SOCK"));
}

// spec-case: ENV-IDENTITY-1
test "environment identity passes telemetry directories to children but never keys them" {
    try std.testing.expectEqual(.placement, identity.classify("MYLANG_TEST_TELEMETRY_DIR"));
    try std.testing.expectEqual(.placement, identity.classify("SELKA_VERIFICATION_TELEMETRY_DIR"));
    try std.testing.expectEqual(.keyed, identity.classify("SELKA_VERIFICATION_TELEMETRY_DIRS"));
}

// spec: ENV-IDENTITY-2
test "environment identity digest reproduces the golden guest and host fixture digests" {
    var variables: [512]identity.Variable = undefined;
    var tools: [16]identity.Tool = undefined;
    const digest = identity.digest(.guest, fixtureVariables(&variables), fixtureTools(&tools));
    try std.testing.expectEqualStrings(std.mem.trimEnd(u8, guest_digest_text, "\n"), &digest);
    const host = identity.digest(.host, fixtureVariables(&variables), fixtureTools(&tools));
    try std.testing.expectEqualStrings(std.mem.trimEnd(u8, host_digest_text, "\n"), &host);
}

// spec-case: ENV-IDENTITY-2
test "environment identity digest ignores launcher and placement variables and input order" {
    var variables: [512]identity.Variable = undefined;
    var tools: [16]identity.Tool = undefined;
    const fixture = fixtureVariables(&variables);
    const tool_list = fixtureTools(&tools);
    const base = identity.digest(.guest, fixture, tool_list);
    try std.testing.expectEqualStrings(&base, &digestWith(.guest, fixture, tool_list, "CODEX_THREAD_ID", "another-thread"));
    try std.testing.expectEqualStrings(&base, &digestWith(.guest, fixture, tool_list, "TERM", "dumb"));
    try std.testing.expectEqualStrings(&base, &digestWith(.guest, fixture, tool_list, "PWD", "/elsewhere"));
    try std.testing.expectEqualStrings(&base, &digestWith(.guest, fixture, tool_list, "TMPDIR", "/other/tmp"));
    try std.testing.expectEqualStrings(&base, &digestWith(.guest, fixture, tool_list, "MYLANG_TEST_TELEMETRY_DIR", "/request/7"));
    std.mem.reverse(identity.Variable, fixture);
    std.mem.reverse(identity.Tool, tool_list);
    try std.testing.expectEqualStrings(&base, &identity.digest(.guest, fixture, tool_list));
}

// spec-case: ENV-IDENTITY-2
test "environment identity digest changes with a keyed variable or a tool digest" {
    var variables: [512]identity.Variable = undefined;
    var tools: [16]identity.Tool = undefined;
    const fixture = fixtureVariables(&variables);
    const tool_list = fixtureTools(&tools);
    const base = identity.digest(.guest, fixture, tool_list);
    try std.testing.expect(!std.mem.eql(u8, &base, &digestWith(.guest, fixture, tool_list, "MYLANG_MEMORY_LIMIT", "1G")));
    try std.testing.expect(!std.mem.eql(u8, &base, &digestWith(.guest, fixture, tool_list, "LD_PRELOAD", "/lib.so")));
    const other: [64]u8 = @splat('2');
    tool_list[0].digest = &other;
    try std.testing.expect(!std.mem.eql(u8, &base, &identity.digest(.guest, fixture, tool_list)));
    try std.testing.expect(!std.mem.eql(u8, &base, &identity.digest(.guest, fixture, tool_list[1..])));
}

// spec-case: ENV-IDENTITY-2
test "environment identity host digest keys host variables that the guest digest ignores" {
    var variables: [512]identity.Variable = undefined;
    var tools: [16]identity.Tool = undefined;
    const fixture = fixtureVariables(&variables);
    const tool_list = fixtureTools(&tools);
    const guest = identity.digest(.guest, fixture, tool_list);
    const host = identity.digest(.host, fixture, tool_list);
    try std.testing.expect(!std.mem.eql(u8, &guest, &host));
    try std.testing.expectEqualStrings(&guest, &digestWith(.guest, fixture, tool_list, "PYTHONPATH", "/other/site"));
    try std.testing.expectEqualStrings(&guest, &digestWith(.guest, fixture, tool_list, "LANG", "de_DE.UTF-8"));
    try std.testing.expect(!std.mem.eql(u8, &host, &digestWith(.host, fixture, tool_list, "PYTHONPATH", "/other/site")));
    try std.testing.expect(!std.mem.eql(u8, &host, &digestWith(.host, fixture, tool_list, "LANG", "de_DE.UTF-8")));
    try std.testing.expect(!std.mem.eql(u8, &host, &digestWith(.host, fixture, tool_list, "MYLANG_MEMORY_LIMIT", "1G")));
    try std.testing.expectEqualStrings(&host, &digestWith(.host, fixture, tool_list, "CODEX_THREAD_ID", "another-thread"));
    try std.testing.expectEqualStrings(&host, &digestWith(.host, fixture, tool_list, "TMPDIR", "/other/tmp"));
}

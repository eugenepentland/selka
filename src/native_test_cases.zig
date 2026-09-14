//! Discover exported guest tests and validate declarative case settings.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const expected_key = "expected";
/// Invalid test settings never silently disable a discovered case.
pub const Error = error{ InvalidTestCases, UnknownTestCase, MissingTestExpectation, OutOfMemory };
/// Borrowed schema and settings values with an owned discovery result slice.
pub const Case = struct {
    name: []const u8,
    function: std.json.Value,
    arguments: std.json.Value,
    expected: std.json.Value,
    skip: ?[]const u8,
    providers: std.json.Value,
    settings: std.json.Value,
};
/// Select exported test_ functions, validate all configuration keys, and retain skips.
pub fn discover(allocator: std.mem.Allocator, schema: std.json.Value, cases: std.json.Value, pattern: []const u8) Error![]Case {
    if (cases != .null and cases != .object) return error.InvalidTestCases;
    const functions = v.array(v.get(schema, "functions"));
    if (cases == .object) {
        var entries = cases.object.iterator();
        while (entries.next()) |entry| {
            const found = for (functions) |function| {
                const name = v.text(v.get(function, "name"));
                if (testName(name) and std.mem.eql(u8, name, entry.key_ptr.*)) break true;
            } else false;
            if (!found) return error.UnknownTestCase;
        }
    }
    var selected: std.ArrayList(Case) = .empty;
    errdefer selected.deinit(allocator);
    for (functions) |function| {
        const name = v.text(v.get(function, "name"));
        if (!testName(name) or !matches(pattern, name)) continue;
        try selected.append(allocator, try makeCase(function, v.get(cases, name)));
    }
    return selected.toOwnedSlice(allocator);
}
fn testName(name: []const u8) bool {
    const start = if (std.mem.lastIndexOf(u8, name, "::")) |i| i + 2 else 0;
    return std.mem.startsWith(u8, name[start..], "test_");
}
fn makeCase(function: std.json.Value, settings: std.json.Value) Error!Case {
    if (settings != .null and settings != .object) return error.InvalidTestCases;
    if (settings == .object) {
        var entries = settings.object.iterator();
        while (entries.next()) |entry| {
            const valid = for ([_][]const u8{ "arguments", expected_key, "skip", "providers" }) |name| {
                if (std.mem.eql(u8, entry.key_ptr.*, name)) break true;
            } else false;
            if (!valid) return error.InvalidTestCases;
        }
    }
    const arguments = v.get(settings, "arguments");
    const skip = v.get(settings, "skip");
    const providers = v.get(settings, "providers");
    if (arguments != .null and arguments != .object) return error.InvalidTestCases;
    if (skip != .null and skip != .string) return error.InvalidTestCases;
    if (providers != .null and providers != .object) return error.InvalidTestCases;
    const reason = if (skip == .string and skip.string.len != 0) skip.string else null;
    const explicit = settings == .object and settings.object.contains(expected_key);
    const is_bool = std.mem.eql(u8, v.text(v.get(function, "result")), "bool");
    if (reason == null) {
        if (!explicit and !is_bool) return error.MissingTestExpectation;
    }
    return .{
        .name = v.text(v.get(function, "name")),
        .function = function,
        .arguments = if (arguments == .null) .{ .object = .empty } else arguments,
        .expected = if (explicit) v.get(settings, expected_key) else .{ .bool = true },
        .skip = reason,
        .providers = providers,
        .settings = settings,
    };
}
/// Case-sensitive shell-style wildcard matching, including bracket ranges. A
/// pattern carrying no wildcard is a plain substring of the qualified name, so
/// `--filter parse` selects every module's `test_parse*` without a glob.
pub fn matches(pattern: []const u8, name: []const u8) bool {
    if (std.mem.indexOfAny(u8, pattern, "*?[") == null) return std.mem.indexOf(u8, name, pattern) != null;
    var p: usize = 0;
    var n: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (n < name.len) {
        if (p < pattern.len and pattern[p] == '*') {
            p += 1;
            star = p;
            retry = n;
            continue;
        }
        const width = token(pattern[p..], point(name[n..]));
        if (width != 0) {
            p += width;
            n += widthAt(name[n..]);
        } else if (star) |restart| {
            retry += widthAt(name[retry..]);
            n = retry;
            p = restart;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}
fn widthAt(bytes: []const u8) usize {
    if (bytes.len == 0) return 0;
    return @min(bytes.len, std.unicode.utf8ByteSequenceLength(bytes[0]) catch 1);
}
fn point(bytes: []const u8) u21 {
    return std.unicode.utf8Decode(bytes[0..widthAt(bytes)]) catch bytes[0];
}
fn token(pattern: []const u8, character: u21) usize {
    if (pattern.len == 0) return 0;
    if (pattern[0] == '?') return 1;
    if (pattern[0] != '[') return if (point(pattern) == character) widthAt(pattern) else 0;
    const negated = pattern.len > 1 and pattern[1] == '!';
    const first: usize = if (negated) 2 else 1;
    const search = first + @intFromBool(first < pattern.len and pattern[first] == ']');
    const end = std.mem.indexOfScalarPos(u8, pattern, search, ']') orelse return if (character == '[') 1 else 0;
    return if (classContains(pattern[first..end], character) != negated) end + 1 else 0;
}
fn classContains(pattern: []const u8, character: u21) bool {
    var i: usize = 0;
    while (i < pattern.len) {
        const low = point(pattern[i..]);
        i += widthAt(pattern[i..]);
        if (i + 1 < pattern.len and pattern[i] == '-') {
            i += 1;
            const high = point(pattern[i..]);
            i += widthAt(pattern[i..]);
            if (character >= low and character <= high) return true;
        } else if (character == low) return true;
    }
    return false;
}

// spec: NATIVE-TEST-1
test "test discovery rejects unknown configuration and missing typed expectations" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"schema":{"functions":[{"name":"checks::test_number","result":"i64"}]},"unknown":{"other":{}},"skip":{"checks::test_number":{"skip":"hardware"}}}
    , .{});
    defer parsed.deinit();
    const schema = v.get(parsed.value, "schema");
    try std.testing.expectError(error.InvalidTestCases, discover(std.testing.allocator, schema, .{ .bool = true }, "*"));
    try std.testing.expectError(error.UnknownTestCase, discover(std.testing.allocator, schema, v.get(parsed.value, "unknown"), "none"));
    try std.testing.expectError(error.MissingTestExpectation, discover(std.testing.allocator, schema, .null, "*"));
    const skipped = try discover(std.testing.allocator, schema, v.get(parsed.value, "skip"), "checks::*");
    defer std.testing.allocator.free(skipped);
    try std.testing.expectEqualStrings("hardware", skipped[0].skip.?);
    const empty = try discover(std.testing.allocator, schema, .null, "other::*");
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}
// spec-case: NATIVE-TEST-4
test "a wildcard-free filter selects by substring of the qualified name" {
    try std.testing.expect(matches("test_sum", "prog042::test_sum"));
    try std.testing.expect(matches("prog042", "prog042::test_sum"));
    try std.testing.expect(matches("", "prog042::test_sum"));
    try std.testing.expect(!matches("test_product", "prog042::test_sum"));
    try std.testing.expect(!matches("Test_sum", "prog042::test_sum"));
}
test "test filters match qualified names and bracket exclusions" {
    try std.testing.expect(matches("*::test_[a-c]?", "checks::test_b1"));
    try std.testing.expect(!matches("*::test_[!a-c]?", "checks::test_b1"));
    try std.testing.expect(matches("*a*b", "xxaaabyb"));
    try std.testing.expect(!matches("*a*b", "xxaac"));
    try std.testing.expect(matches("?", "é"));
    try std.testing.expect(matches("[é-ê]", "ê"));
    try std.testing.expect(matches("[]]", "]"));
    try std.testing.expect(!matches("[a]", "[a]"));
}

test "boolean tests default to true with empty named arguments and preserve explicit expectations" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"schema":{"functions":[{"name":"main::test_ok","result":"bool"},{"name":"main::helper","result":"bool"}]},"cases":{"main::test_ok":{"expected":false}}}
    , .{});
    defer parsed.deinit();
    const defaults = try discover(std.testing.allocator, v.get(parsed.value, "schema"), .null, "*");
    defer std.testing.allocator.free(defaults);
    try std.testing.expectEqual(@as(usize, 1), defaults.len);
    try std.testing.expect(defaults[0].expected.bool);
    try std.testing.expectEqual(@as(usize, 0), defaults[0].arguments.object.count());
    const explicit = try discover(std.testing.allocator, v.get(parsed.value, "schema"), v.get(parsed.value, "cases"), "*");
    defer std.testing.allocator.free(explicit);
    try std.testing.expect(!explicit[0].expected.bool);
}

test "case settings reject misspelled expectation controls" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"schema":{"functions":[{"name":"test_ok","result":"bool"}]},"cases":{"test_ok":{"expect":false}}}
    , .{});
    defer parsed.deinit();
    try std.testing.expectError(error.InvalidTestCases, discover(std.testing.allocator, v.get(parsed.value, "schema"), v.get(parsed.value, "cases"), "*"));
}

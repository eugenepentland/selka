//! The compiler's ownership relation agrees with its public code index and reference.
const std = @import("std");
const t = std.testing;
const rules = @import("ownership_rules.zig");
const codes = @import("diagnostic_codes.zig");
const diagnostic = @import("diagnostic.zig");

fn codeIndex(code: []const u8) ?usize {
    for (rules.entries, 0..) |entry, index| if (std.mem.eql(u8, entry.code, code)) return index;
    return null;
}

fn checkRegistry() !void {
    var described: [std.meta.tags(rules.Rule).len]bool = @splat(false);
    for (rules.definitions) |definition| {
        const index = @backingInt(definition.rule);
        try t.expect(!described[index]);
        try t.expect(definition.description.len != 0);
        described[index] = true;
    }
    try t.expect(std.mem.allEqual(bool, &described, true));
    for (rules.entries, 0..) |entry, index| {
        try t.expect(entry.rules.len != 0);
        for (rules.entries[0..index]) |earlier| try t.expect(!std.mem.eql(u8, entry.code, earlier.code));
        var seen: [std.meta.tags(rules.Rule).len]bool = @splat(false);
        for (entry.rules) |rule| {
            try t.expect(!seen[@backingInt(rule)]);
            seen[@backingInt(rule)] = true;
            try t.expect(rules.valid(.{ .code = entry.code, .rule = rule }));
        }
        var found = false;
        for (codes.entries) |code| {
            if (!std.mem.eql(u8, code.code, entry.code)) continue;
            found = true;
            try t.expectEqualSlices(rules.Rule, entry.rules, code.rules);
        }
        try t.expect(found);
    }
    for (codes.entries) |code| try t.expectEqualSlices(rules.Rule, rules.rulesFor(code.code), code.rules);
}

fn checkCodeMap(document: []const u8) !void {
    var seen: [rules.entries.len]bool = @splat(false);
    var inside = false;
    var header = false;
    var separator = false;
    var lines = std.mem.splitScalar(u8, document, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "## Refusal codes mapped to rules")) {
            inside = true;
            continue;
        }
        if (!inside) continue;
        if (std.mem.startsWith(u8, line, "## ")) break;
        if (std.mem.indexOfScalar(u8, line, '|') == null) continue;
        if (std.mem.eql(u8, line, "| Code | Rules |")) {
            if (header) return error.TestUnexpectedResult;
            header = true;
            continue;
        }
        if (std.mem.eql(u8, line, "| --- | --- |")) {
            if (!header or separator) return error.TestUnexpectedResult;
            separator = true;
            continue;
        }
        if (!header or !separator) return error.TestUnexpectedResult;
        var cells = std.mem.splitScalar(u8, line, '|');
        if ((cells.next() orelse return error.TestUnexpectedResult).len != 0) return error.TestUnexpectedResult;
        const spelling = std.mem.trim(u8, cells.next() orelse return error.TestUnexpectedResult, " \t");
        if (!std.mem.startsWith(u8, spelling, "`E_") or !std.mem.endsWith(u8, spelling, "`")) return error.TestUnexpectedResult;
        const code = spelling[1 .. spelling.len - 1];
        const index = codeIndex(code) orelse return error.TestUnexpectedResult;
        try t.expect(!seen[index]);
        seen[index] = true;
        var actual: [std.meta.tags(rules.Rule).len]bool = @splat(false);
        var names = std.mem.tokenizeAny(u8, cells.next() orelse return error.TestUnexpectedResult, " `,");
        if (std.mem.trim(u8, cells.next() orelse return error.TestUnexpectedResult, " \t").len != 0) return error.TestUnexpectedResult;
        if (cells.next() != null) return error.TestUnexpectedResult;
        var count: usize = 0;
        while (names.next()) |name| {
            const rule = std.meta.stringToEnum(rules.Rule, name) orelse return error.TestUnexpectedResult;
            try t.expect(!actual[@backingInt(rule)]);
            actual[@backingInt(rule)] = true;
            count += 1;
        }
        try t.expectEqual(rules.entries[index].rules.len, count);
        for (rules.entries[index].rules) |rule| try t.expect(actual[@backingInt(rule)]);
    }
    try t.expect(inside);
    try t.expect(header and separator);
    try t.expect(std.mem.allEqual(bool, &seen, true));
}

test "ownership registry has closed unique rules and agrees with diagnostic reference entries" {
    try checkRegistry();
    try t.expectEqual(@as(usize, 54), rules.definitions.len);
    try t.expect(!rules.valid(.{ .code = "E_IMMUTABLE", .rule = .M3 }));
    try t.expect(!rules.valid(.{ .code = "E_TYPE", .rule = .T1 }));
    try t.expectEqual(@as(usize, 0), rules.rulesFor("E_BORROW_VIEWS_REMOVED").len);
}

test "ownership living reference code map exactly matches the compiler registry" {
    const document = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/ownership-rules.md", t.allocator, .limited(1 << 20));
    defer t.allocator.free(document);
    try checkCodeMap(document);
}

fn canonicalMap(a: std.mem.Allocator) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(a);
    try text.appendSlice(a, "## Refusal codes mapped to rules\n\n| Code | Rules |\n| --- | --- |\n");
    for (rules.entries) |entry| {
        try text.print(a, "| `{s}` | ", .{entry.code});
        for (entry.rules, 0..) |rule, index| {
            if (index != 0) try text.appendSlice(a, ", ");
            try text.appendSlice(a, @tagName(rule));
        }
        try text.appendSlice(a, " |\n");
    }
    return text.toOwnedSlice(a);
}

test "ownership code map rejects one missing extra duplicate or mislabeled row" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const complete = try canonicalMap(a);
    try checkCodeMap(complete);
    const first = std.mem.indexOf(u8, complete, "| `E_").?;
    const end = first + std.mem.indexOfScalar(u8, complete[first..], '\n').? + 1;
    const missing = try std.mem.concat(a, u8, &.{ complete[0..first], complete[end..] });
    try t.expectError(error.TestUnexpectedResult, checkCodeMap(missing));
    const extra = try std.mem.concat(a, u8, &.{ complete, "| `E_UNKNOWN_OWNERSHIP_CODE` | B3 |\n" });
    try t.expectError(error.TestUnexpectedResult, checkCodeMap(extra));
    const duplicate = try std.mem.concat(a, u8, &.{ complete, complete[first..end] });
    try t.expectError(error.TestUnexpectedResult, checkCodeMap(duplicate));
    const wrong = try std.mem.replaceOwned(u8, a, complete, "| `E_BORROW_MIXED` | R5 |", "| `E_BORROW_MIXED` | R4 |");
    try t.expectError(error.TestUnexpectedResult, checkCodeMap(wrong));
}

fn checkMalformedCodeMapColumns(a: std.mem.Allocator, complete: []const u8) !void {
    for ([_][]const u8{ "| `E_SINGLE_OWNER_MOVED` | B3 | extra |", "| `E_SINGLE_OWNER_MOVED` | B3" }) |row| {
        const malformed = try std.mem.replaceOwned(u8, a, complete, "| `E_SINGLE_OWNER_MOVED` | B3 |", row);
        try t.expectError(error.TestUnexpectedResult, checkCodeMap(malformed));
    }
}

test "ownership code map rejects unquoted extra and malformed table rows" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const complete = try canonicalMap(a);
    const rows = [_][]const u8{
        "| E_UNKNOWN_OWNERSHIP_CODE | B3 |\n",
        "E_UNKNOWN_OWNERSHIP_CODE | B3 |\n",
        "| | B3 |\n",
    };
    for (rows) |row| {
        const malformed = try std.mem.concat(a, u8, &.{ complete, row });
        try t.expectError(error.TestUnexpectedResult, checkCodeMap(malformed));
    }
    const unquoted = try std.mem.replaceOwned(u8, a, complete, "`E_SINGLE_OWNER_MOVED`", "E_SINGLE_OWNER_MOVED");
    try t.expectError(error.TestUnexpectedResult, checkCodeMap(unquoted));
    try checkMalformedCodeMapColumns(a, complete);
}

test "ownership Sink preserves explicit rule through fixes and transfer witnesses" {
    var sink: diagnostic.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    const span = @import("source.zig").Span{ .start = 0, .end = 1 };
    try t.expect(sink.failOwnershipFix(.{ .code = "E_OWN_MARKER", .rule = .W2 }, span, "marker", .{ .span = span, .text = "own " }) == error.SourceError);
    try t.expectEqual(diagnostic.Rule.W2, sink.items.items[0].provenance.rule.?);
    try t.expect(sink.items.items[0].provenance.fix != null);
    try t.expect(sink.failOwnershipTransfer(.{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 }, span, span, span) == error.SourceError);
    try t.expectEqual(diagnostic.Severity.err, sink.items.items[1].severity);
    try t.expectEqual(diagnostic.Rule.B3, sink.items.items[1].provenance.rule.?);
    try t.expect(sink.items.items[1].provenance.origin != null);
    try t.expect(sink.failOwnershipTransfer(.{ .code = "E_RESULT_CONSUMED", .rule = .L1 }, span, span, span) == error.SourceError);
    try t.expectEqual(diagnostic.Severity.err, sink.items.items[2].severity);
    try t.expectEqual(diagnostic.Rule.L1, sink.items.items[2].provenance.rule.?);
    try t.expect(sink.failOwnershipCallSite(.{ .code = "E_MUTATION_MARKER", .rule = .M3 }, span, "write mut", .{ .span = span, .message = "mut value", .role = .alternative }, "func grow(mut value: int[])") == error.SourceError);
    try t.expectEqual(diagnostic.Rule.M3, sink.items.items[3].provenance.rule.?);
    try t.expectEqual(diagnostic.Role.alternative, sink.items.items[3].related.?.role);
    try t.expectEqual(diagnostic.Role.signature, sink.items.items[3].provenance.requirement.?.role);
}

test "D4 prototype row 14 maps file storage only to P4" {
    try t.expectEqualSlices(rules.Rule, &.{.P4}, rules.rulesFor("E_WITH_RESOURCE"));
    try t.expect(!rules.valid(.{ .code = "E_WITH_RESOURCE", .rule = .T4 }));
}

test "declared borrow diagnostics use R4 and the mutation budget code is retired" {
    try t.expectEqualSlices(rules.Rule, &.{.R4}, rules.rulesFor("E_BORROW_SOURCE"));
    try t.expectEqualSlices(rules.Rule, &.{.R4}, rules.rulesFor("E_BORROW_UNDECLARED"));
    try t.expectEqual(@as(usize, 0), rules.rulesFor("E_MUTATION_LIMIT").len);
}

test "explicit move markers share a code and retire the call-only spelling" {
    try t.expectEqualSlices(rules.Rule, &.{ .B2, .B9, .W2 }, rules.rulesFor("E_OWN_MARKER"));
    try t.expectEqual(@as(usize, 0), rules.rulesFor("E_OWN_ARGUMENT").len);
}

test "evaluation temporary limitations have no live refusal code" {
    try t.expectEqual(@as(usize, 0), rules.rulesFor("E_SINGLE_OWNER_UNSUPPORTED").len);
    for (codes.entries) |entry| try t.expect(!std.mem.eql(u8, entry.code, "E_SINGLE_OWNER_UNSUPPORTED"));
}

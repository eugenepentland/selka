//! The repair for a match that lacks a case a standard enum gained by splitting an older one.
//!
//! When a standard-library change gives an enum a case that its values used to reach as another case (the limit
//! refusals of `http.Error` were `Malformed`, a version it will not speak was `Unsupported`), every exhaustive
//! match over the enum stops checking. Copying the arm of the old case under the new case's name is exactly what
//! the program did before, so the repair is certain and `selka fix` can apply it.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// One case added to an enum by splitting an older case: before the change, every value of `added` reached a
/// match as `formerly`, with a payload of the same shape.
pub const Split = struct { enum_name: []const u8, added: []const u8, formerly: []const u8 };

/// The splits the standard library has made, the enum named as the type catalog names it.
pub const splits = [_]Split{
    .{ .enum_name = "http::Error", .added = "HeaderTooLarge", .formerly = "Malformed" },
    .{ .enum_name = "http::Error", .added = "BodyTooLarge", .formerly = "Malformed" },
    .{ .enum_name = "http::Error", .added = "UnsupportedVersion", .formerly = "Unsupported" },
};

/// The case that `added` of `enum_name` used to be, or null when `added` is not a split case.
pub fn formerly(enum_name: []const u8, added: []const u8) ?[]const u8 {
    for (splits) |split| {
        if (std.mem.eql(u8, split.enum_name, enum_name) and std.mem.eql(u8, split.added, added)) return split.formerly;
    }
    return null;
}

/// An arm of the source match: the span of its case name and the span of its body statement.
pub const Arm = struct { head: source.Span, body: source.Span };

/// The edit that inserts, right after `arm`, a copy of the whole arm under the case name `added`. The copy keeps
/// the arm's pattern (a `Err(` wrapper, a qualifier, named payload labels) and its body. Null when the arm is not
/// one line of `case` followed by its own indented body, which is when copying text would not be certain.
pub fn copyArm(allocator: std.mem.Allocator, src: source.Source, arm: Arm, added: []const u8) std.mem.Allocator.Error!?diagnostic.Edit {
    const bytes = src.bytes;
    if (arm.head.start >= arm.head.end or arm.head.end > bytes.len or arm.body.end > bytes.len or arm.body.start < arm.head.end) return null;
    var start = arm.head.start;
    while (start > 0 and bytes[start - 1] != '\n') start -= 1;
    var cursor = start;
    while (cursor < arm.head.start and (bytes[cursor] == ' ' or bytes[cursor] == '\t')) cursor += 1;
    const indent = cursor - start;
    if (!std.mem.startsWith(u8, bytes[cursor..], "case ")) return null;
    var end = arm.body.end;
    while (end > arm.body.start and std.ascii.isWhitespace(bytes[end - 1])) end -= 1;
    while (end < bytes.len and bytes[end] != '\n') end += 1;
    // Every later line of the range belongs to this arm: blank, or indented deeper than the `case` line.
    var line = std.mem.indexOfScalarPos(u8, bytes[0..end], start, '\n');
    while (line) |newline| {
        const next = newline + 1;
        if (next >= end) break;
        var depth: usize = 0;
        while (next + depth < end and (bytes[next + depth] == ' ' or bytes[next + depth] == '\t')) depth += 1;
        const blank = next + depth >= end or bytes[next + depth] == '\n';
        if (!blank and depth <= indent) return null;
        line = std.mem.indexOfScalarPos(u8, bytes[0..end], next, '\n');
    }
    const text = try std.mem.concat(allocator, u8, &[_][]const u8{ "\n", bytes[start..arm.head.start], added, bytes[arm.head.end..end] });
    return .{ .span = .{ .start = end, .end = end }, .text = text };
}

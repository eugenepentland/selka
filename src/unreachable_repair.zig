//! The refusal of a statement that follows one which always leaves its block (`E_UNREACHABLE`): the message that says
//! why the earlier statement leaves, and the repair that deletes a trailing `return` or `fail` that could never run.
//! The concrete and the generic checker share it, so both word and repair the refusal alike.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// The message and the optional repair of one `E_UNREACHABLE` refusal.
pub const Refusal = struct { message: []const u8, fix: ?diagnostic.Fix };

/// How a statement that always leaves its block does so.
const Leave = enum { returns, fails, other };

/// The refusal of `siblings[index]`, a statement that follows a statement of its block that always leaves. `plain` is
/// the message for a statement whose way of leaving needs no explanation (a `return`, a `break`). The repair deletes the
/// line of the statement when it is a `return` or `fail` and the last statement of its block; any other statement may
/// be one the author put there by mistake, so it keeps the refusal alone.
pub fn refusal(allocator: std.mem.Allocator, src: source.Source, statements: []const ast.Statement, siblings: []const ast.StatementId, index: usize, plain: []const u8) std.mem.Allocator.Error!Refusal {
    if (index == 0) return .{ .message = plain, .fix = null };
    return .{
        .message = try explain(allocator, src, statements, siblings[index - 1]) orelse plain,
        .fix = deletion(src, statements, siblings, index),
    };
}

/// Say why `earlier` leaves its block when it is a `match` or an `if` whose every branch does; null for any other
/// statement, whose way of leaving its own words already tell.
fn explain(allocator: std.mem.Allocator, src: source.Source, statements: []const ast.Statement, earlier: ast.StatementId) std.mem.Allocator.Error!?[]const u8 {
    const stmt = statements[@backingInt(earlier)];
    const noun = switch (stmt.data) {
        .branch => "branch of the `if`",
        // A bind-or-else test (`if x is Some(v):`) is parsed as a `match`; the author's own word names it.
        .match => if (std.mem.startsWith(u8, src.bytes[stmt.span.start..], "match")) "arm of the `match`" else "branch of the `if`",
        else => return null,
    };
    const verb = switch (leave(statements, earlier)) {
        .returns => "returns",
        .fails => "fails",
        .other => "leaves",
    };
    const message = try std.fmt.allocPrint(allocator, "every {s} at line {d} {s}, so this statement cannot run", .{ noun, src.locate(stmt.span.start).line, verb });
    return message;
}

/// How `id` leaves its block: `returns` or `fails` when every way out of it is a `return` or a `fail`.
fn leave(statements: []const ast.Statement, id: ast.StatementId) Leave {
    return switch (statements[@backingInt(id)].data) {
        .ret => .returns,
        .fail => .fails,
        .block => |children| if (children.len == 0) .other else leave(statements, children[children.len - 1]),
        .with_scope => |scope| leave(statements, scope.body),
        .branch => |branch| if (branch.else_body) |other| common(leave(statements, branch.then_body), leave(statements, other)) else .other,
        .match => |match| arms(statements, match.arms),
        else => .other,
    };
}

/// The way every arm of a `match` leaves, or `other` when they differ.
fn arms(statements: []const ast.Statement, list: []const ast.MatchArm) Leave {
    if (list.len == 0) return .other;
    var way = leave(statements, list[0].body);
    for (list[1..]) |arm| way = common(way, leave(statements, arm.body));
    return way;
}

/// What two branches have in common.
fn common(a: Leave, b: Leave) Leave {
    return if (a == b) a else .other;
}

/// The repair that deletes the whole line of `siblings[index]`, newline included, when it is a `return` or a `fail` that
/// ends its block and shares its line with nothing but indentation and an optional comment; null for any other layout.
fn deletion(src: source.Source, statements: []const ast.Statement, siblings: []const ast.StatementId, index: usize) ?diagnostic.Fix {
    if (index + 1 != siblings.len) return null;
    const stmt = statements[@backingInt(siblings[index])];
    switch (stmt.data) {
        .ret, .fail => {},
        else => return null,
    }
    const limit = moduleEnd(src, stmt.span) orelse return null;
    const bytes = src.bytes[0..limit];
    if (stmt.span.end > limit or stmt.span.start > stmt.span.end) return null;
    const start = if (std.mem.lastIndexOfScalar(u8, bytes[0..stmt.span.start], '\n')) |newline| newline + 1 else 0;
    if (std.mem.trim(u8, bytes[start..stmt.span.start], " \t").len != 0) return null;
    const newline = std.mem.indexOfScalarPos(u8, bytes, stmt.span.end, '\n');
    const tail = std.mem.trim(u8, bytes[stmt.span.end .. newline orelse bytes.len], " \t\r");
    if (tail.len != 0 and tail[0] != '#') return null;
    return .{ .edit = .{ .span = .{ .start = start, .end = if (newline) |at| at + 1 else bytes.len }, .text = "" } };
}

/// The end of the source file that holds `span`: a project's modules are joined by one separator byte each, which a
/// repair must not delete.
fn moduleEnd(src: source.Source, span: source.Span) ?usize {
    if (src.origins.len == 0) return src.bytes.len;
    const origin = src.originalSpan(span) catch return null;
    const module = src.origins[origin.input];
    return module.start + module.original.bytes.len;
}

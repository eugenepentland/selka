//! `on fail:` clauses (D-FFI-15, `docs/results-and-options.md#cleanup-on-failure`).
//!
//! `on fail: STATEMENT` (or `on fail:` and a block) registers cleanup for the failure exits after it, to the end of its
//! block. The parser rewrites each failure exit in a clause's reach into the bind-or-else `match` the language already
//! checks: its failure arm runs the armed clauses, latest first, then `fail`s the error. So the type checker, the L1
//! analysis, the `@linear` rule, ownership, Core and the validators see only forms they see today. This module holds the
//! clause state the parser carries through a function body, the token scans that arm and disarm clauses, and the
//! messages of `E_ON_FAIL`.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const source = @import("source.zig");

/// The code of every refusal of an `on fail:` form.
pub const code = "E_ON_FAIL";

/// One registered clause: its block, where it was written, the owners it consumes (each name after `own` in it), and
/// where it stands in the reading of its reach.
pub const Clause = struct {
    body: ast.StatementId,
    span: source.Span,
    owners: []const []const u8,
    flags: Flags = .{},
};

/// Where a clause stands at the point being read.
pub const Flags = struct {
    /// It runs on a failure exit here.
    armed: bool = true,
    /// A failure exit has taken it (one that none takes is refused).
    reached: bool = false,
    /// Its parsed block went to an exit, so later exits take copies.
    original_used: bool = false,
    /// A nested block that falls through consumed one of `owners`: the statement holding that block disarms it.
    consumed_inside: bool = false,
    /// A block disarmed it: then an unreached clause is left to the `@linear` rule, which says why a branch that
    /// consumes the owner differs from one that does not.
    branch_disarmed: bool = false,
    /// The clause is a `detach` loop's put-back (`loop_detach.zig`), armed over the loop's body by the parser.
    detach: bool = false,
};

/// Whether an `on fail:` clause the program wrote is armed among `clauses`.
pub fn userArmed(clauses: []const Clause) bool {
    for (clauses) |clause| if (clause.flags.armed and !clause.flags.detach) return true;
    return false;
}

/// Whether a `detach` loop's clause is armed among `clauses`.
pub fn detachArmed(clauses: []const Clause) bool {
    for (clauses) |clause| if (clause.flags.armed and clause.flags.detach) return true;
    return false;
}

/// What the parser knows about `on fail:` while it reads one function body.
pub const State = struct {
    /// The clauses of the enclosing blocks, in the order they were written.
    clauses: std.ArrayList(Clause) = .empty,
    /// Whether the function being read declares `fails`.
    fails: bool = false,
    /// Whether the parser is inside a clause's own statements, and how many loops it has opened there.
    inside: struct { clause: bool = false, loops: usize = 0 } = .{},
    /// The first token of the statement being read, until its first block opens: a head that consumes an owner
    /// (`match own token:`) disarms the clause before the blocks it heads are read.
    head: ?usize = null,
    /// The keyword of each `try` read while a clause is registered, in source order: a statement's check finds the ones in
    /// its head by their bytes, a format string's holes included.
    tries: std.ArrayList(source.Span) = .empty,

    /// Record the keyword of a `try` just read, when a clause could run on it.
    pub fn noteTry(self: *State, allocator: std.mem.Allocator, keyword: source.Span) std.mem.Allocator.Error!void {
        if (self.clauses.items.len != 0) try self.tries.append(allocator, keyword);
    }

    /// The first `try` read inside the bytes `head` other than the one that starts at `whole`: a `try` in a call's argument
    /// or an operand, which the rewrite that runs the clauses does not cover. Null when there is none.
    pub fn operandTry(self: *const State, head: source.Span, whole: ?usize) ?source.Span {
        for (self.tries.items) |keyword| {
            if (keyword.start < head.start or keyword.start >= head.end) continue;
            if (whole != null and keyword.start == whole.?) continue;
            return keyword;
        }
        return null;
    }
};

/// Why a clause in a function that does not fail is refused.
pub const not_failing = "`on fail:` runs on a failure exit, and this function declares no `fails`: the clause could never run";
/// Why a clause no failure exit reaches is refused.
pub const unreached = "no failure exit reaches this `on fail:` (no `try` or `fail` follows it in its block while it is armed): the clause never runs";
/// Why a clause that leaves or fails is refused.
pub const leaves = "an `on fail:` clause runs while a failure leaves the function: it cannot `try`, `fail`, `return`, `break`, `continue` " ++
    "or hold another `on fail:`; handle a fallible call's result in it (`_ = close(own conn)` or a `match`)";
/// Why a `try` in a call's argument is refused in a clause's reach: the rewrite that runs the clauses covers a statement's
/// whole value, and it could not move the `try` out of the call without changing the order the arguments run in.
pub const argument_position = "in the reach of an `on fail:` clause, `try` is not a call's argument or an operand: the clauses run on a `try` " ++
    "that is a declaration's value (`const value = try f()`) or a statement of its own; declare the value first, then pass or use it";

/// Why a clause that consumes an owner declared after it is refused.
pub const declared_after = "this declaration comes after the `on fail:` that consumes it, so the clause would name a binding that " ++
    "did not exist where it was written; write the clause after the declaration";
/// Why a `try` in a position the rewrite does not cover is refused.
pub const position = "in the reach of an `on fail:` clause, `try` is a declaration's value (`const value = try f()`) or a statement of " ++
    "its own (`try f()`, `_ = try f()`); declare the value first, then use it";

/// The names the clause tokens `[start, end)` consume: each identifier after an `own` (`own conn`, `own pair.token`).
pub fn owners(allocator: std.mem.Allocator, src: source.Source, tokens: []const lex.Token, start: usize, end: usize) std.mem.Allocator.Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var index = start;
    while (index + 1 < end) : (index += 1) {
        const name = ownedAt(src, tokens, index) orelse continue;
        try names.append(allocator, name);
    }
    return names.items;
}

/// Whether the tokens `[start, end)` consume one of `names`: an `own NAME` among them.
pub fn consumes(src: source.Source, tokens: []const lex.Token, start: usize, end: usize, names: []const []const u8) bool {
    var index = start;
    while (index + 1 < end) : (index += 1) {
        const name = ownedAt(src, tokens, index) orelse continue;
        for (names) |owner| if (std.mem.eql(u8, owner, name)) return true;
    }
    return false;
}

/// The identifier `own` marks at token `index`, or null when token `index` is not an `own` before an identifier.
fn ownedAt(src: source.Source, tokens: []const lex.Token, index: usize) ?[]const u8 {
    if (tokens[index].tag != .ident or tokens[index + 1].tag != .ident) return null;
    if (!std.mem.eql(u8, src.text(tokens[index].span), "own")) return null;
    return src.text(tokens[index + 1].span);
}

/// Whether the statement at `index` of `statements` leaves or fails, the forms a clause cannot hold; `loops` is how many
/// loops the clause has opened around it (a `break` or `continue` there ends one of them, not the clause).
pub fn leavesClause(statement: ast.Statement, nodes: []const ast.Node, loops: usize) bool {
    return switch (statement.data) {
        .fail, .ret => true,
        .loop_exit => loops == 0,
        .binding => |binding| isPropagate(nodes, binding.value),
        .discard => |value| isPropagate(nodes, value),
        .assignment => |assignment| isPropagate(nodes, assignment.value),
        else => false,
    };
}

/// Whether a block that ends with statement `last` leaves it (a `return`, `fail`, `break` or `continue`, or a rewritten
/// exit or bind-or-else that ends with one) rather than falling through to the statement after it.
pub fn leavesBlock(statements: []const ast.Statement, last: ast.StatementId) bool {
    const statement = statements[@backingInt(last)];
    return switch (statement.data) {
        .ret, .fail, .loop_exit => true,
        .block => |children| children.len != 0 and leavesBlock(statements, children[children.len - 1]),
        .match => |match| {
            for (match.arms) |arm| if (arm.alternatives.role == .success) return leavesBlock(statements, arm.body);
            return false;
        },
        else => false,
    };
}

/// The end of a statement's own tokens in `[start, end)`: a compound statement's head, up to the block it opens (its
/// blocks were read as statements of their own), or all of a simple statement.
pub fn headEnd(tokens: []const lex.Token, start: usize, end: usize) usize {
    var index = start;
    while (index < end) : (index += 1) if (tokens[index].tag == .indent) return index;
    return end;
}

/// Whether node `id` is a `try`.
pub fn isPropagate(nodes: []const ast.Node, id: ast.NodeId) bool {
    return nodes[@backingInt(id)].data == .propagate;
}

/// The `try` a statement holds in a position the rewrite does not cover (`return try`, `x = try`, `fail try`), or null.
/// An assignment to a field or an element (`r.a = try f()`, `xs[i] += try f()`, TRYFIELD) is the same position as
/// `x = try f()`: the clauses would not run on its failure, so it is refused like that one.
pub fn uncovered(statement: ast.Statement, nodes: []const ast.Node) ?ast.NodeId {
    const value: ast.NodeId = switch (statement.data) {
        .ret => |returned| returned,
        .fail => |failed| failed,
        .assignment => |assignment| assignment.value,
        .yield_value => |yielded| yielded,
        .discard => |discarded| placeValue(nodes, discarded) orelse return null,
        else => return null,
    };
    return if (isPropagate(nodes, value)) value else null;
}

/// Where the `try` that is a statement's whole value starts, for the statements whose whole-value `try` is not refused in a
/// clause's reach: a declaration and a statement of its own (which the rewrite covers), and a `with` resource.
pub fn wholeTry(statement: ast.Statement, nodes: []const ast.Node) ?usize {
    const value: ast.NodeId = switch (statement.data) {
        .binding => |binding| binding.value,
        .discard => |discarded| discarded,
        .with_scope => |scope| scope.resource orelse return null,
        else => return null,
    };
    return if (isPropagate(nodes, value)) nodes[@backingInt(value)].span.start else null;
}

/// The value an assignment to a field or an element stores, or null when node `id` is not one.
fn placeValue(nodes: []const ast.Node, id: ast.NodeId) ?ast.NodeId {
    return switch (nodes[@backingInt(id)].data) {
        .field_assignment => |assignment| assignment.value,
        .index_assignment => |assignment| assignment.value,
        .list_operation => |operation| if (operation.kind == .write and operation.arguments.len == 2) operation.arguments[1] else null,
        else => null,
    };
}

test "own markers name the owners a clause consumes and the statements that disarm it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = "finalize(host, own insert)\nclose(own conn.db, mut other)\n";
    const src = try source.Source.init(arena.allocator(), "clause.selka", text);
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = arena.allocator() };
    const tokens = try lex.lex(arena.allocator(), text, &sink);
    const named = try owners(arena.allocator(), src, tokens, 0, tokens.len);
    try std.testing.expectEqual(@as(usize, 2), named.len);
    try std.testing.expectEqualStrings("insert", named[0]);
    try std.testing.expectEqualStrings("conn", named[1]);
    try std.testing.expect(consumes(src, tokens, 0, tokens.len, &.{"conn"}));
    try std.testing.expect(!consumes(src, tokens, 0, tokens.len, &.{"other"}));
}

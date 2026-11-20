//! `const NAME = EXPR else FAILURE:` followed by a block that leaves: the bind-or-else statement.
//!
//! The parser builds the `match` it stands for. The failure arm (`Err(e)`, `Err(_)`, `None` or a bare `else:`) holds the
//! block that must leave; the success arm binds the payload to NAME and holds every statement after the declaration, to the
//! end of the enclosing block. Both arms carry a `role` instead of a case name, because the source spells neither `Ok` nor
//! `Some`: the checker finds the success and failure cases of the Option or Result by their position in its schema. All
//! the rest, the payload ownership, the scope of the names and the checks on the arms, is the `match`'s own.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

/// The code of an operand that is neither an Option nor a Result.
pub const operand_code = "E_ELSE_OPERAND";
/// The code of a failure pattern other than `Err(e)`, `Err(_)`, `None` or a bare `else:`.
pub const pattern_code = "E_ELSE_PATTERN";
/// The code of an `else` block that can fall through to the code after the declaration.
pub const leave_code = "E_ELSE_FALLTHROUGH";
/// Why an operand is refused.
pub const operand_message = "`else` after a declaration unwraps an Option or a Result; use `match` for any other value";
/// Why a failure pattern is refused.
pub const pattern_message = "the failure of a bind-or-else is written `Err(e)`, `Err(_)` or `None` (a bare `else:` takes an Option's `None`); use `match` for any other pattern";
/// Why a block that can continue is refused.
pub const leave_message = "the `else` block of a bind-or-else must leave the enclosing block: end it with `return`, `fail`, `break` or `continue`; " ++
    "to handle the failure and go on, write `if CALL is Err(e):` (`is None` for an Option) or a `match` with an arm for each case";

/// A bare `else:` over a Result (F-60): the operand's source text, the error type's name, the declaration of the called
/// function when there is one, and whether `Err(_)` may drop the error (it does not itself need handling).
/// `call` is true when the operand is a call (it "can fail"), false for a value that holds a Result.
pub const BareElse = struct { operand: []const u8, failure: []const u8, called: ?source.Span, droppable: bool, call: bool };

/// Whether `arm` is the failure arm of a bind-or-else written as a bare `else:` or as `else None:`: a failure pattern
/// without a binding, which a Result's failure case refuses.
pub fn bareElse(src: source.Source, arm: ast.MatchArm) bool {
    if (arm.alternatives.role != .failure or arm.bindings.len != 0) return false;
    return std.mem.eql(u8, src.text(arm.name), "else") or std.mem.eql(u8, src.text(arm.name), "None");
}

/// Refuse a bare `else:` over a Result, whose failure case carries the error: say that the operand can fail and name the
/// two patterns that say what the block does with the failure, with a note at the called function. The repair inserts
/// ` Err(_)` after `else` when the error may be dropped; it is certain because a bare `else:` already stands for the
/// failure case and `Err(_)` names that case and discards its payload, which nothing could have read.
pub fn refuseBareElse(src: source.Source, sink: *diagnostic.Sink, arm: ast.MatchArm, bare: BareElse) diagnostic.Error {
    const shown = if (bare.operand.len > 40) bare.operand[0..40] else bare.operand;
    const ellipsis: []const u8 = if (bare.operand.len > 40) "..." else "";
    const what: []const u8 = if (bare.call) "can fail with" else "is a Result whose failure carries";
    const none = std.mem.eql(u8, src.text(arm.name), "None");
    const written: []const u8 = if (none) "`else None:` takes an Option's absent value" else "a bare `else:` takes only an Option's `None`";
    const message = std.fmt.allocPrint(sink.allocator, "`{s}{s}` {s} {s}, so the `else` must say what it does with the " ++
        "failure: `else Err(_):` drops it and `else Err(reason):` binds it to use ({s})", .{ shown, ellipsis, what, bare.failure, written }) catch return error.OutOfMemory;
    var item: diagnostic.Diagnostic = .{ .code = diagnostic.pattern_payload, .span = arm.name, .message = message };
    if (bare.called) |declaration| item.related = .{ .span = declaration, .message = "the called function, which can fail" };
    if (!bare.droppable) {
        sink.items.append(sink.allocator, item) catch return error.OutOfMemory;
        return error.SourceError;
    }
    const edit: diagnostic.Edit = if (none) .{ .span = arm.name, .text = "Err(_)" } else .{ .span = .{ .start = arm.ty.start, .end = arm.ty.start }, .text = " Err(_)" };
    try sink.appendFix(item, edit);
    return error.SourceError;
}

/// The message for `CALL else Err(e):` written as a statement (F-76): `else` unwraps the value that a declaration or `_ =`
/// takes, and a statement that is only an expression has none to bind. `operand` is the expression's source text (the
/// word `CALL` when it is too long to repeat three times) and `pattern` the failure pattern written after the `else`, or
/// null for a bare `else:`. It names the form that tests a call giving nothing back (`if CALL is Err(e):`, the shape the
/// `W_MATCH_IS` warning prefers) and the two that take or drop a value.
pub fn statementElseMessage(allocator: std.mem.Allocator, operand: []const u8, pattern: ?[]const u8) std.mem.Allocator.Error![]const u8 {
    if (pattern) |written| return std.fmt.allocPrint(allocator, "`else` needs a value to bind, and a statement that is only `{s}` has none: " ++
        "write `if {s} is {s}:` when the call gives nothing back, or drop or keep its value with " ++
        "`_ = {s} else {s}:` or `const NAME = {s} else {s}:`", .{ operand, operand, written, operand, written, operand, written });
    return std.fmt.allocPrint(allocator, "`else` needs a value to bind, and a statement that is only `{s}` has none: " ++
        "write `if {s} is Err(e):` (a call that can fail) or `if {s} is None:` (an Option) when it gives nothing back, " ++
        "or drop or keep its value with `_ = {s} else:` or `const NAME = {s} else:`", .{ operand, operand, operand, operand, operand });
}

/// The pieces of an assignment written with an `else` block, as source text: the name assigned, the assignment operator,
/// the value (the word `VALUE` when it is too long to repeat three times) and the `else` clause up to its colon.
pub const AssignmentElse = struct { target: []const u8, operator: []const u8, operand: []const u8, clause: []const u8 };

/// The message for `x = f() else Err(m):` (SP1-F-5): the `else` unwraps the value into a new name, so it belongs to a
/// declaration, and an assignment to the name that already exists takes no block. It names the two forms that do the job.
pub fn assignmentElseMessage(allocator: std.mem.Allocator, written: AssignmentElse) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "`{s}` unwraps the value into a new name, so it belongs to a declaration and not to an assignment " ++
        "to the existing `{s}`: write `const value = {s} {s}` and then `{s} {s} value`, or `match {s}:` with an arm for each case", .{
        written.clause, written.target, written.operand, written.clause, written.target, written.operator, written.operand,
    });
}

/// The pieces of an assignment to a field or an element written with an `else` block, as source text: the place, whether it
/// is an element (else a field), the assignment operator, the value (the word `VALUE` when it is too long to repeat) and the
/// `else` clause up to its colon.
pub const PlaceElse = struct { place: []const u8, element: bool, operator: []const u8, operand: []const u8, clause: []const u8 };

/// The message for `pax.size = f() else:` and `xs[i] = f() else:` (SP1B-F-3), in the voice of `assignmentElseMessage`: the
/// `else` unwraps the value into a new name, so it belongs to a declaration. It names the three forms that do the job for a
/// place: the declaration and the assignment after it, `try` in a function that can fail, and `if CALL is Ok(value):` (`Some`
/// for an Option) with the assignment inside. The new name is `value` unless the operand already uses that word.
pub fn placeElseMessage(allocator: std.mem.Allocator, written: PlaceElse) std.mem.Allocator.Error![]const u8 {
    const result = std.mem.startsWith(u8, written.clause, "else Err");
    const name: []const u8 = if (std.mem.indexOf(u8, written.operand, "value") == null) "value" else "item";
    return std.fmt.allocPrint(allocator, "`{s}` unwraps the value into a new name, so it belongs to a declaration and not to an assignment " ++
        "to the {s} `{s}`: write `const {s} = {s} {s}` and then `{s} {s} {s}`, `{s} {s} try {s}` in a function that {s}, " ++
        "or `if {s} is {s}({s}):` with `{s} {s} {s}` inside", .{
        written.clause,                                  if (written.element) "element" else "field", written.place,
        name,                                            written.operand,                             written.clause,
        written.place,                                   written.operator,                            name,
        written.place,                                   written.operator,                            written.operand,
        if (result) "can fail" else "returns an Option", written.operand,                             if (result) "Ok" else "Some",
        name,                                            written.place,                               written.operator,
        name,
    });
}

/// The `E_TRY_RETURN` message for `try` on an Option in a function that does not return an Option (F-57). `fails` is
/// whether the function declares `fails`; `optional` whether its successful result is an Option (`-> T? fails E`).
pub fn optionTryMessage(fails: bool, optional: bool) []const u8 {
    if (fails and optional) return "`try` on an Option is refused in a function that can also fail: there `try` passes on a " ++
        "failure, not an absent value; write `const x = CALL else:` with `return None` in its block";
    if (fails) return "`try` on an Option returns `None`, which this function cannot return: its result is a value that " ++
        "can fail, not an Option; write `const x = CALL else:` with a block that leaves";
    return "`try` on an Option returns `None` from the function, so the function must return an Option (`-> T?`); " ++
        "otherwise write `const x = CALL else:` with a block that leaves";
}

/// Refuse the arm of a bind-or-else failure whose block can continue; `at` is where the block ends.
pub fn requireLeaves(sink: *diagnostic.Sink, arm: ast.MatchArm, terminates: bool, at: source.Span) diagnostic.Error!void {
    if (arm.alternatives.role != .failure or terminates) return;
    return sink.failRelated(leave_code, at, leave_message, .{ .span = arm.name, .message = "the failure case this block handles" });
}

/// Refuse a bind-or-else over a value that is neither an Option nor a Result; `unwrappable` answers for the value's type.
pub fn requireOperand(sink: *diagnostic.Sink, arms: []const ast.MatchArm, unwrappable_value: bool, at: source.Span) diagnostic.Error!void {
    if (unwrappable_value or !isBindOrElse(arms)) return;
    return sink.fail(operand_code, at, operand_message);
}

/// Where the `else` block of a bind-or-else ends: its last statement, or the block itself when it is empty.
pub fn leaveSpan(statements: []const ast.Statement, body: ast.StatementId) source.Span {
    const block = statements[@backingInt(body)];
    if (block.data == .block and block.data.block.len != 0) return statements[@backingInt(block.data.block[block.data.block.len - 1])].span;
    return block.span;
}

/// Whether any arm of a match is an arm of a bind-or-else.
pub fn isBindOrElse(arms: []const ast.MatchArm) bool {
    for (arms) |arm| if (arm.alternatives.role != .named) return true;
    return false;
}

/// The tag of the success or the failure case of a closed case set that holds exactly an Option's two cases (`some`, `none`)
/// or a Result's (`ok`, `err`), or null when the set is anything else. Concrete and symbolic case lists both have `name`.
pub fn roleTag(cases: anytype, role: ast.Role) ?usize {
    if (cases.len != 2) return null;
    const option = hasPair(cases, "some", "none");
    if (!option and !hasPair(cases, "ok", "err")) return null;
    const wanted = switch (role) {
        .success => if (option) "some" else "ok",
        .failure => if (option) "none" else "err",
        .named => return null,
    };
    for (cases, 0..) |case, index| if (std.mem.eql(u8, case.name, wanted)) return index;
    return null;
}

/// Whether a two-case set names exactly these two cases.
fn hasPair(cases: anytype, first: []const u8, second: []const u8) bool {
    return (std.mem.eql(u8, cases[0].name, first) and std.mem.eql(u8, cases[1].name, second)) or
        (std.mem.eql(u8, cases[0].name, second) and std.mem.eql(u8, cases[1].name, first));
}

/// Whether a type is an Option or a Result, the operands a bind-or-else unwraps.
pub fn unwrappable(ty: typed.Type, records: []const typed.Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const variants = records[ty.recordIndex()].shape.variants orelse return false;
    return roleTag(variants.cases, .success) != null;
}

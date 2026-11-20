//! The rules of `@linear` records (D-FFI-11, `docs/records-and-unions.md#linear-records`).
//!
//! A linear record carries the pending-value obligation the L1 analysis tracks (`requires_handling`), so the checker
//! already follows every path an owner takes. This module names the linear cases: an owner left unconsumed, an owner used
//! after it was consumed, the one field read that ends an owner (`own owner.field`), and the uses a linear value refuses.
//! Core sees an ordinary record: none of this reaches Core IR, its validators or its certificates.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const walk = @import("typed_walk.zig");

/// The code of an owner that leaves its scope unconsumed.
pub const unconsumed_code = "E_LINEAR_UNCONSUMED";
/// The code of an owner used after it was consumed.
pub const consumed_code = "E_LINEAR_CONSUMED";
/// The code of every other refused use of a linear value.
pub const use_code = "E_LINEAR_USE";

/// The uses a linear value refuses, each with its own message.
pub const Use = enum {
    discard,
    copy,
    parameter,
    container,
    generic,
    task,
    lent,
    move,
    loop,
    paths,
    projection,
    temporary,
    overwrite,
    read,
    match_lent,
    unwrap_or,
    loan,
    loan_argument,
    loan_callback,
    loan_overlap,

    /// What the refusal says.
    pub fn message(self: Use) []const u8 {
        return switch (self) {
            .discard => "a `@linear` value cannot be discarded; consume it: give it to an `own` parameter, return it, or end it with " ++
                "`own value.field` where the field is kept (`const kept = own value.field`)",
            .copy => "a `@linear` value cannot be copied: two owners would each have to consume it",
            .parameter => "a generic function takes a `@linear` parameter `own` (the callee consumes it) or `mut` (the callee borrows it to " ++
                "write or replace it); a plain `@linear` parameter is a read-only loan only in a function without type parameters",
            .container => "a list, dictionary or set cannot hold a `@linear` value: destroying the container would end its owners unconsumed",
            .generic => "a generic function cannot be instantiated with a `@linear` type: its body is checked once, without the obligation",
            .task => "a `@linear` value cannot cross to a parallel task or come back from one",
            .lent => "a `mut` parameter lends its `@linear` owner; the caller consumes it, the callee cannot",
            .move => "a `@linear` owner moves only with `own`: write `own` before it",
            .loop => "a `@linear` owner declared outside a loop cannot be consumed inside it: the loop runs its body zero or many " ++
                "times; consume it before or after the loop, or declare it inside the body",
            .paths => "every path must leave a `@linear` owner in the same state: consume it on every branch, or on none",
            .projection => "a `@linear` field is taken with `own holder.field`, which consumes the holder, or lent with `mut holder.field`; " ++
                "a plain read would make a second owner of it",
            .temporary => "bind a `@linear` value to a name before reading its fields: the rest of it would be dropped unconsumed",
            .overwrite => "an assignment would end the `@linear` owner it replaces unconsumed; consume it first",
            .read => "this operation would consume a `@linear` owner without ending it (printing, comparing, formatting or " ++
                "converting it); read its fields instead",
            .match_lent => "a `match mut` binding is lent, not owned: it names the matched place, which keeps the owner; read it, " ++
                "write it or lend it with `mut`, and take the owner out with `match own` or `take(mut place)`",
            .unwrap_or => "`unwrap_or` makes its default before it looks at the option and drops it unconsumed when a `@linear` payload is " ++
                "there: take the payload with `match own value:` and make the default in the `None` arm",
            .loan => "a plain parameter is a read-only loan of the caller's `@linear` owner: read it, read its fields or lend it to " ++
                "another plain parameter; it cannot be moved, consumed, written or lent `mut` here. `own` takes the value (declare " ++
                "the parameter `own conn: Conn`), and `mut` lends it to write or replace it",
            .loan_argument => "a plain parameter borrows a `@linear` value for the call and the caller still owns it, so the argument " ++
                "is a named owner or a field of one, of the parameter's own type, written without `own`: a value made for the call " ++
                "would be dropped unconsumed; bind it to a name first, or declare the parameter `own` to take it",
            .loan_overlap => "a plain parameter's loan of a `@linear` owner lasts for the whole call, so the same call cannot also " ++
                "give the owner, a field of it or a record that holds it with `own`, or lend an overlapping place `mut`: the callee " ++
                "could end or replace what it reads through the loan; make the two calls one after the other",
            .loan_callback => "a call through a function value cannot lend a `@linear` value to a plain parameter: call the function " ++
                "by its name, which lends it for the call, or give the value a function whose parameter is `own` or `mut`",
        };
    }
};

/// Refuse a use of a linear value at `span`.
pub fn refuse(sink: *diagnostic.Sink, span: source.Span, use: Use) diagnostic.Error {
    return sink.fail(use_code, span, use.message());
}

/// What ends the path an owner is still live on: the end of its scope (a `return`, a block's end, a `break`), or the failure
/// exit of a `try`, which `on fail:` can end the owner on.
pub const Exit = enum { scope, try_failure };

/// An owner that reaches the end of a path unconsumed; `lent_at` is the scrutinee of a `match mut` that lent it, if any.
pub const Unconsumed = struct { name: []const u8, declaration: source.Span, end: source.Span, lent_at: ?source.Span = null, exit: Exit = .scope };

/// How `own owner.field` ends an owner: where the field's value is kept. A discard `_ = own owner.field` of a list or text field
/// only reads it (`E_OWN_MARKER` in Core) and does not end the owner, so the advice never offers it.
const field_end = "end it with `own {s}.field` where the field is kept (`const kept = own {s}.field`, `return own {s}.field`); " ++
    "`_ = own {s}.field` of a list or text field only reads it";

/// The repair of an owner a `try` would lose when it fails: the clause that ends it on every failure exit after it.
const try_failure_advice = "if this `try` fails the function leaves with `{s}` still live, so end it on that exit with an `on fail:` clause " ++
    "written right after `{s}` is declared, `on fail: close(own {s})` (`close` stands for the function that takes `{s}` as an `own` " ++
    "parameter and ends it; the clause runs on every failure exit after it and never on the success path)";

/// What to do with an owner a `match mut` lent: the match does not end it, so the path must, in one of the four ways.
fn lentAdvice(allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "a `match mut` lends `{s}` to its arms and does not end it; end it on this path: give it to " ++
        "an `own` parameter, return it, move it into another owner (`const next = own {s}`, or `match own {s}:` and consume " ++
        "the payload), or, for a record, " ++ field_end, .{ name, name, name, name, name, name, name });
}

/// Report `owner` unconsumed where the path leaves its scope.
pub fn unconsumed(sink: *diagnostic.Sink, allocator: std.mem.Allocator, owner: Unconsumed) diagnostic.Error {
    if (owner.lent_at) |lent_at| {
        const message = try std.fmt.allocPrint(allocator, "`@linear` owner `{s}` is not consumed before this path leaves its scope: {s}", .{ owner.name, try lentAdvice(allocator, owner.name) });
        return sink.failRelated(unconsumed_code, owner.end, message, .{ .span = lent_at, .message = "`match mut` lends the owner here, without ending it" });
    }
    const message = if (owner.exit == .try_failure) try std.fmt.allocPrint(allocator, "`@linear` owner `{s}` is not consumed before this path leaves its scope: " ++
        try_failure_advice ++ "; or end it before this `try`: give it to an `own` parameter, return it, move it into another owner, or " ++ field_end, .{
        owner.name, owner.name, owner.name, owner.name, owner.name, owner.name, owner.name, owner.name, owner.name,
    }) else try std.fmt.allocPrint(allocator, "`@linear` owner `{s}` is not consumed before this path leaves its scope; give it to an `own` " ++
        "parameter, return it, move it into another owner, or " ++ field_end, .{ owner.name, owner.name, owner.name, owner.name, owner.name });
    return sink.failRelated(unconsumed_code, owner.end, message, .{ .span = owner.declaration, .message = "the owner is declared here" });
}

/// Refuse an assignment to a `@linear` owner that a `match mut` lent: the assignment would end the value the owner holds
/// unconsumed, and the match did not end it either.
pub fn overwriteLent(sink: *diagnostic.Sink, allocator: std.mem.Allocator, span: source.Span, name: []const u8, lent_at: source.Span) diagnostic.Error {
    const message = try std.fmt.allocPrint(allocator, "this assignment would end the `@linear` value `{s}` holds unconsumed: {s}", .{ name, try lentAdvice(allocator, name) });
    return sink.failRelated(use_code, span, message, .{ .span = lent_at, .message = "`match mut` lends the owner here, without ending it" });
}

/// Report a use of `name` after it was consumed at `consumed_at`, when that is known.
pub fn consumed(sink: *diagnostic.Sink, allocator: std.mem.Allocator, use: source.Span, name: []const u8, consumed_at: ?source.Span) diagnostic.Error {
    const message = try std.fmt.allocPrint(allocator, "`@linear` owner `{s}` was already consumed", .{name});
    const at = consumed_at orelse return sink.fail(consumed_code, use, message);
    return sink.failRelated(consumed_code, use, message, .{ .span = at, .message = "consumed here" });
}

/// Whether a local is a payload binding of `match mut`: a place of the matched value, never an owner of its own.
pub fn matchLent(local: typed.Local) bool {
    return local.origin == .pattern and local.mutable and local.ownership.transfer_span == null;
}

/// Whether a local is a `mut` parameter, which lends its owner to the callee.
pub fn lent(local: typed.Local) bool {
    return local.origin == .parameter and local.mutable and !local.ownership.owned_parameter;
}

/// Whether a local is a plain parameter, a read-only loan of the caller's owner for the call (decision LINEAR-LEND): the
/// callee reads it and lends it to another plain parameter, and owes nothing for it.
pub fn loan(local: typed.Local) bool {
    return local.origin == .parameter and !local.mutable and !local.ownership.owned_parameter;
}

/// Refuse a write, a `mut` lend or a replacement of a plain `@linear` parameter, a read-only loan, before the ordinary
/// read-only refusal names the binding.
pub fn refuseLoanWrite(sink: *diagnostic.Sink, records: []const typed.Record, local: typed.Local, span: source.Span) diagnostic.Error!void {
    if (typed.linear(local.ty, records) and loan(local)) return refuse(sink, span, .loan);
}

/// The local a syntax node names when it is a bare name of an active local of a `@linear` type.
pub fn linearName(comptime Checker: type, self: *Checker, id: ast.NodeId) ?typed.LocalId {
    const node = self.syntax.nodes.items[@backingInt(id)];
    if (node.data != .name) return null;
    const slot = self.active.get(self.src.text(node.data.name)) orelse return null;
    if (!typed.linear(self.locals.items[@backingInt(slot)].ty, self.catalog.records)) return null;
    return slot;
}

/// The `@linear` local a field chain (`a.b.c`) or a bare name is rooted at, or null.
pub fn linearRoot(comptime Checker: type, self: *Checker, id: ast.NodeId) ?typed.LocalId {
    var current = id;
    while (self.syntax.nodes.items[@backingInt(current)].data == .field) current = self.syntax.nodes.items[@backingInt(current)].data.field.base;
    return linearName(Checker, self, current);
}

/// A field read out of a `@linear` holder: a read of a linear field is a projection that only `own` or `mut` may take
/// (`borrowing` is set for both, and for a further field read through it), and any read out of a holder that is not a
/// named owner (a call result) would drop the holder, unless `own` takes it.
pub fn checkProjection(comptime Checker: type, self: *Checker, base: ast.NodeId, out: typed.Node, borrowing: bool) diagnostic.Error!void {
    const records = self.catalog.records;
    if (borrowing or out.data != .field) return;
    if (typed.linear(out.ty, records)) return refuse(self.sink, out.span, .projection);
    const holder = self.nodes.items[@backingInt(out.data.field.base)].ty;
    if (typed.linear(holder, records) and linearRoot(Checker, self, base) == null) return refuse(self.sink, out.span, .temporary);
}

/// `own holder.field` takes one field and ends the holder: a field of that holder which holds a `@linear` value, other
/// than the one taken, would be dropped unconsumed. Checked at every level of the chain (`own a.b.c`).
pub fn checkFieldTake(sink: *diagnostic.Sink, allocator: std.mem.Allocator, nodes: []const typed.Node, records: []const typed.Record, taken: typed.NodeId) diagnostic.Error!void {
    var current = nodes[@backingInt(taken)];
    while (current.data == .field) {
        const holder = nodes[@backingInt(current.data.field.base)].ty;
        if (holder.isAggregate() and holder.recordIndex() < records.len) {
            for (records[holder.recordIndex()].fields, 0..) |field, index| {
                if (index == current.data.field.index or !typed.linear(field.ty, records)) continue;
                const message = try std.fmt.allocPrint(allocator, "`own` of this field ends its holder and would drop the `@linear` field `{s}` " ++
                    "unconsumed; a holder that must be ended field by field is not supported", .{field.name});
                return sink.fail(use_code, current.span, message);
            }
        }
        current = nodes[@backingInt(current.data.field.base)];
    }
}

/// A record with more than one field that holds a `@linear` value could never be ended (`own` of one field drops the
/// other), so the declaration is refused, naming both fields.
pub fn checkLinearFields(sink: *diagnostic.Sink, allocator: std.mem.Allocator, records: []const typed.Record, record: typed.Record) diagnostic.Error!void {
    var first: ?[]const u8 = null;
    for (record.fields) |field| {
        if (!typed.linear(field.ty, records)) continue;
        if (first) |name| {
            const message = try std.fmt.allocPrint(allocator, "a record holds at most one field with a `@linear` value: `{s}` and `{s}` both do, " ++
                "and ending the record with `own record.field` would drop the other; put each owner in its own binding or record", .{ name, field.name });
            return sink.fail(use_code, record.declaration, message);
        }
        first = field.name;
    }
}

/// `own owner.field` (a chain of fields rooted at a `@linear` local) consumes the owner: the one way to end it without
/// handing it on. Any other `own` operand is left to the ordinary rules.
pub fn consumeField(comptime Checker: type, self: *Checker, inner: ast.NodeId) diagnostic.Error!void {
    var current = self.syntax.nodes.items[@backingInt(inner)];
    if (current.data != .field) return;
    while (current.data == .field) current = self.syntax.nodes.items[@backingInt(current.data.field.base)];
    if (current.data != .name) return;
    const slot = self.active.get(self.src.text(current.data.name)) orelse return;
    const local = &self.locals.items[@backingInt(slot)];
    if (!typed.linear(local.ty, self.catalog.records)) return;
    if (lent(local.*)) return refuse(self.sink, current.span, .lent);
    if (loan(local.*)) return refuse(self.sink, current.span, .loan);
    if (!local.ownership.transfer_available) return consumed(self.sink, self.allocator, current.span, local.name, local.ownership.transfer_span);
    local.ownership.transfer_available = false;
    local.ownership.transfer_span = current.span;
}

/// The whole-program linear rules, on the checked program (every concrete function, generic instances included): no
/// collection or fixed array holds a `@linear` value, no generic instance takes a `@linear` type argument, and no
/// `parallel` task takes or returns one.
pub fn checkProgram(allocator: std.mem.Allocator, program: typed.Program, sink: *diagnostic.Sink, stubs: []const ?@import("origins.zig").Fact) diagnostic.Error!void {
    const records = program.records;
    for (program.functions, 0..) |function, index| {
        if (@import("origins.zig").standIn(stubs, index) != null or function.policy.c_abi or function.policy.host != null) continue;
        try checkReads(allocator, program, function, sink);
    }
    for (program.functions) |function| {
        for (function.type_arguments) |argument| if (typed.linear(argument, records)) return refuse(sink, function.declaration, .generic);
        for (function.scope.locals) |local| if (holdsLinearElements(local.ty, records)) return refuse(sink, local.declaration, .container);
        if (holdsLinearElements(function.signature.return_type, records)) return refuse(sink, function.declaration, .container);
    }
    for (program.nodes) |node| {
        if (holdsLinearElements(node.ty, records)) return refuse(sink, node.span, .container);
        switch (node.data) {
            .task_submit => |submit| {
                const call = program.nodes[@backingInt(submit.call)];
                if (typed.linear(call.ty, records)) return refuse(sink, node.span, .task);
                if (call.data == .call) for (call.data.call.arguments) |argument| {
                    if (typed.linear(program.nodes[@backingInt(argument)].ty, records)) return refuse(sink, node.span, .task);
                };
            },
            .task_result => if (typed.linear(node.ty, records)) return refuse(sink, node.span, .task),
            else => {},
        }
    }
}

/// Whether a type is a list, dictionary, set or fixed array whose elements, keys or values are `@linear`.
fn holdsLinearElements(ty: typed.Type, records: []const typed.Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.shape.array) |array| return array.length != 0 and typed.linear(array.element, records);
    if (!record.isCollection()) return false;
    if (record.shape.buffer) |element| if (typed.linear(element, records)) return true;
    if (record.collection.key) |key| if (typed.linear(key, records)) return true;
    return false;
}

/// Every read of a `@linear` local consumes it, so a read is allowed only where the owner moves on: the value of a
/// binding, an assignment, a `return` or a `match`; a field of a value being built or a case payload; the base of a field
/// read (which borrows); a call argument written `own` or passed to a `mut` parameter; and a `try`. Any other operation
/// (printing, comparing, formatting, converting) would end the owner without consuming it, and is refused. A call argument
/// given to a plain parameter of a `@linear` type is lent for the call (decision LINEAR-LEND).
fn checkReads(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function, sink: *diagnostic.Sink) diagnostic.Error!void {
    var walker = try walk.Walker.init(allocator, program, function.scope.body);
    defer walker.deinit();
    var path: std.ArrayList(walk.Item) = .empty;
    defer path.deinit(allocator);
    while (try walker.advance()) |step| {
        const complete = path.items.len >= step.depth;
        path.shrinkRetainingCapacity(@min(path.items.len, step.depth));
        try path.append(allocator, step.item);
        if (step.item != .expression or step.depth == 0 or !complete) continue;
        const node = program.nodes[@backingInt(step.item.expression)];
        if (node.data != .local or !typed.linear(node.ty, program.records)) continue;
        if (!movesOn(program, path.items[step.depth - 1], step.item.expression, node)) return refuse(sink, node.span, .read);
    }
}

/// Whether `parent` is a position a `@linear` local `child` may be read in (`checkReads`).
fn movesOn(program: typed.Program, parent: walk.Item, child: typed.NodeId, node: typed.Node) bool {
    switch (parent) {
        .statement => |id| return switch (program.statements[@backingInt(id)].data) {
            .ret, .initialize, .assign, .match, .with_scope, .block => true,
            else => false,
        },
        .expression => |id| return switch (program.nodes[@backingInt(id)].data) {
            .record, .variant, .field, .propagate, .block_value, .update, .place_exchange => true,
            .call => |call| callPosition(program, call.function, call.arguments, child, node),
            .invoke => node.own,
            else => false,
        },
    }
}

/// A call argument moves on when it is written `own` or passed to a `mut` parameter, and is lent when it is passed to a
/// plain parameter of a `@linear` type of a function without type arguments (the checker took it as a borrow).
fn callPosition(program: typed.Program, callee: typed.FunctionId, arguments: []const typed.NodeId, child: typed.NodeId, node: typed.Node) bool {
    if (node.own) return true;
    const position = std.mem.indexOfScalar(typed.NodeId, arguments, child) orelse return false;
    const function = program.functions[@backingInt(callee)];
    if (std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(position)) != null) return true;
    const owned = position < function.scope.own_parameters.len and function.scope.own_parameters[position];
    return function.type_arguments.len == 0 and !owned and typed.linear(node.ty, program.records);
}

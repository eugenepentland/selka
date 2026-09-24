//! Contract clauses in the checker. `@requires` conditions are checked at
//! function entry, after the parameters are bound; `@ensures` conditions at
//! every normal return, with `result` naming the returned value and each
//! `old(...)` read from a hidden local captured at entry; `@invariant`
//! conditions wherever a value of the carrying record or domain is built or
//! changed. Each clause is checked as an ordinary Boolean expression and
//! placed in the body as a typed assertion that records its kind, so lowering,
//! both native backends and every cache treat it like an `assert` whose trap
//! message names the contract (`R_REQUIRES`, `R_ENSURES`, `R_INVARIANT`).
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const byte_literal = @import("byte_literal.zig");
const collections = @import("collection_lower.zig");
const Error = diagnostic.Error;
const Span = source.Span;

/// Diagnostic code for a `result` an `@ensures` clause cannot name.
pub const result_code = "E_CONTRACT_RESULT";
/// Diagnostic code for a contract condition that is not effect-free.
pub const effect_code = "E_CONTRACT_EFFECT";
/// Diagnostic code for an `old(...)` in the wrong place or nested.
pub const old_code = "E_CONTRACT_OLD";
/// Diagnostic code for `old(...)` of a value that shares mutable storage.
pub const old_shared_code = "E_CONTRACT_OLD_SHARED";

/// The trap code each contract kind raises. The checked assertion's static
/// message begins with this code and `: `; the native runtime reads the prefix
/// back to report the contract's own code instead of `R_ASSERT`.
pub fn trapCode(kind: typed.AssertionKind) []const u8 {
    return switch (kind) {
        .statement => "R_ASSERT",
        .requires => "R_REQUIRES",
        .ensures => "R_ENSURES",
        .invariant => "R_INVARIANT",
    };
}

/// One contract trap message: `CODE: subject kind `clause`[: message]`. The
/// clause text has its whitespace runs folded to one space, so a condition
/// written across lines still reads as one.
pub fn trapMessage(allocator: std.mem.Allocator, kind: typed.AssertionKind, subject: []const u8, clause: []const u8, note: ?[]const u8) std.mem.Allocator.Error![]const u8 {
    var folded: std.ArrayList(u8) = .empty;
    defer folded.deinit(allocator);
    var space = false;
    for (std.mem.trim(u8, clause, " \t\r\n")) |byte| {
        const blank = byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
        if (blank and space) continue;
        space = blank;
        try folded.append(allocator, if (blank) ' ' else byte);
    }
    const word = @tagName(kind);
    if (note) |text| return std.fmt.allocPrint(allocator, "{s}: {s} {s} `{s}`: {s}", .{ trapCode(kind), subject, word, folded.items, text });
    return std.fmt.allocPrint(allocator, "{s}: {s} {s} `{s}`", .{ trapCode(kind), subject, word, folded.items });
}

/// One `old(...)` call of the function being checked and the hidden local its
/// entry value was captured in.
const Old = struct { node: ast.NodeId, slot: typed.LocalId };

/// One invariant-carrying record or domain: its clauses, the name its traps
/// report, and whether `unwrap(self)` needs the domain's own access.
pub const Invariant = struct { name: []const u8, clauses: []const ast.Attribute, domain: bool };

/// Contract state the checker carries. `ensures`, `olds`, `subject` and
/// `parameters` describe the function being checked and are reset for every
/// body; `invariants` is built once per check.
pub const State = struct {
    ensures: []const ast.Attribute = &.{},
    olds: []const Old = &.{},
    subject: []const u8 = "",
    parameters: usize = 0,
    invariants: std.AutoHashMapUnmanaged(typed.Type, Invariant) = .empty,
    /// The clause kind whose condition is being checked, if any; a `mut`
    /// call-site marker or a `?` is rejected while it is set.
    checking: ?typed.AssertionKind = null,
};

/// The span of a `name` node spelled `text` inside the expression `root`, or
/// null when the expression never names it. Walks every expression identity
/// the node's payload holds; statements never occur inside a condition.
pub fn mention(program: ast.Program, src: source.Source, root: ast.NodeId, text: []const u8) ?Span {
    return mentionValue(ast.NodeId, program, src, root, text, 0);
}

fn mentionValue(comptime T: type, program: ast.Program, src: source.Source, value: T, text: []const u8, depth: usize) ?Span {
    if (depth > 256) return null;
    if (T == ast.NodeId) {
        const index = @backingInt(value);
        if (index >= program.nodes.items.len) return null;
        const node = program.nodes.items[index];
        if (node.data == .name and std.mem.eql(u8, src.text(node.data.name), text)) return node.data.name;
        return mentionValue(@TypeOf(node.data), program, src, node.data, text, depth + 1);
    }
    if (T == Span or T == ast.StatementId) return null;
    switch (@typeInfo(T)) {
        .@"struct" => |info| inline for (info.field_names, info.field_types) |name, Field| {
            if (mentionValue(Field, program, src, @field(value, name), text, depth)) |span| return span;
        },
        .@"union" => |info| inline for (info.field_names, info.field_types) |name, Field| {
            if (std.meta.activeTag(value) == @field(std.meta.Tag(T), name))
                return mentionValue(Field, program, src, @field(value, name), text, depth);
        },
        .optional => |info| if (value) |present| return mentionValue(info.child, program, src, present, text, depth),
        .pointer => |info| if (info.size == .slice and info.child != u8) for (value) |item| {
            if (mentionValue(info.child, program, src, item, text, depth)) |span| return span;
        },
        else => {},
    }
    return null;
}

/// The Boolean, message and span of one clause, ready to check.
const Clause = struct { attribute: ast.Attribute, kind: typed.AssertionKind, subject: []const u8 };

/// Bind contract checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Index every record and domain carrying `@invariant` by its checked type.
        pub fn indexInvariants(self: *Checker) Error!void {
            return impl.indexInvariants(Checker, self);
        }
        /// Whether one syntax node is an `old(...)` an `@ensures` check bound in advance.
        pub fn contractSeeded(self: *Checker, index: usize) bool {
            return impl.contractSeeded(Checker, self, index);
        }
        /// Check the preconditions and capture the `old(...)` values of the function being checked.
        pub fn contractPrologue(self: *Checker, function: ast.Function) Error![]const typed.StatementId {
            return impl.contractPrologue(Checker, self, function);
        }
        /// The statement one `return value` becomes in a function with `@ensures`.
        pub fn contractReturn(self: *Checker, value: typed.NodeId, span: Span) Error!@FieldType(typed.Statement, "data") {
            return impl.contractReturn(Checker, self, value, span);
        }
        /// Check `@invariant` wherever the current body built or changed a carrying value.
        pub fn enforceInvariants(self: *Checker, first: usize) Error!void {
            return impl.enforceInvariants(Checker, self, first);
        }
    };
}
const impl = @This();

/// Index every non-generic record and domain that carries `@invariant`
/// by its checked type, once per check.
fn indexInvariants(comptime Checker: type, self: *Checker) Error!void {
    for (self.catalog.records) |record| {
        const attributes = ast.attributesOf(self.syntax, record.declaration);
        var clauses: std.ArrayList(ast.Attribute) = .empty;
        for (attributes) |attribute| if (attribute.kind == .invariant) try clauses.append(self.allocator, attribute);
        if (clauses.items.len == 0) continue;
        try self.contract.invariants.put(self.allocator, record.id, .{
            .name = self.src.text(record.declaration),
            .clauses = try clauses.toOwnedSlice(self.allocator),
            .domain = record.shape.domain != null,
        });
    }
}

/// Whether one syntax node is an `old(...)` call whose value an
/// `@ensures` check has already bound, so the expression walk treats
/// it as a checked temporary.
fn contractSeeded(comptime Checker: type, self: *Checker, index: usize) bool {
    if (self.contract.checking != .ensures) return false;
    for (self.contract.olds) |old| if (@backingInt(old.node) == index) return true;
    return false;
}

/// Check the `@requires` clauses and capture each `old(...)` of the
/// function whose parameters were just bound. Returns the statements
/// that run before its body, in source order: the preconditions, then
/// the captures. Leaves the `@ensures` clauses for every return.
fn contractPrologue(comptime Checker: type, self: *Checker, function: ast.Function) Error![]const typed.StatementId {
    self.contract.ensures = &.{};
    self.contract.olds = &.{};
    const attributes = ast.attributesOf(self.syntax, function.name);
    var any = false;
    for (attributes) |attribute| any = any or attribute.kind == .requires or attribute.kind == .ensures;
    if (!any) return &.{};
    const subject = if (function.policy.owner) |owner|
        try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.src.text(owner), self.src.text(function.name) })
    else
        self.src.text(function.name);
    self.contract.subject = subject;
    self.contract.parameters = function.signature.parameters.len;
    var statements: std.ArrayList(typed.StatementId) = .empty;
    var ensures: std.ArrayList(ast.Attribute) = .empty;
    for (attributes) |attribute| switch (attribute.kind) {
        .requires => try statements.append(self.allocator, try clauseStatement(Checker, self, .{ .attribute = attribute, .kind = .requires, .subject = subject })),
        .ensures => try ensures.append(self.allocator, attribute),
        else => {},
    };
    if (ensures.items.len == 0) return statements.toOwnedSlice(self.allocator);
    try requireResultName(Checker, self, function, ensures.items);
    var olds: std.ArrayList(Old) = .empty;
    for (ensures.items) |attribute| for (attribute.olds) |call| {
        const captured = try captureOld(Checker, self, call);
        try olds.append(self.allocator, captured.old);
        try statements.append(self.allocator, captured.statement);
    };
    self.contract.ensures = try ensures.toOwnedSlice(self.allocator);
    self.contract.olds = try olds.toOwnedSlice(self.allocator);
    return statements.toOwnedSlice(self.allocator);
}

/// The statement one `return value` becomes in a function with
/// `@ensures`: the value is held in a hidden local, every postcondition
/// is checked against it, and the local is returned. A `Result` return
/// checks only its `Ok` payload; an `Err` return skips the clauses.
fn contractReturn(comptime Checker: type, self: *Checker, value: typed.NodeId, span: Span) Error!@FieldType(typed.Statement, "data") {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const value_type = self.nodes.items[@backingInt(value)].ty;
    if (typed.resultShape(value_type, self.catalog.records)) |shape| {
        const held = try hiddenLocal(Checker, self, "<return>", value_type, span);
        const payload = try hiddenLocal(Checker, self, "result", shape.ok_type, span);
        const checks = try ensuresBlock(Checker, self, payload, span);
        const arms = try self.allocator.alloc(typed.MatchArm, 2);
        arms[0] = .{ .tag = shape.ok_tag, .slot = payload, .body = checks };
        arms[1] = .{ .tag = shape.error_tag, .slot = null, .body = try b.stmt(.{ .block = &.{} }) };
        const initialize = try b.stmt(.{ .initialize = .{ .slot = held, .value = value } });
        const dispatch = try b.stmt(.{ .match = .{ .value = try b.read(held), .arms = arms } });
        return .{ .block = try self.allocator.dupe(typed.StatementId, &.{ initialize, dispatch, try returnLocal(Checker, self, held, span) }) };
    }
    const named = value_type != .unit;
    if (!named and self.nodes.items[@backingInt(value)].data == .unit) {
        const checks = try ensuresBlock(Checker, self, null, span);
        const id: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = .{ .ret = value } });
        return .{ .block = try self.allocator.dupe(typed.StatementId, &.{ checks, id }) };
    }
    const held = try hiddenLocal(Checker, self, if (named) "result" else "<return>", value_type, span);
    const initialize = try b.stmt(.{ .initialize = .{ .slot = held, .value = value } });
    const checks = try ensuresBlock(Checker, self, if (named) held else null, span);
    return .{ .block = try self.allocator.dupe(typed.StatementId, &.{ initialize, checks, try returnLocal(Checker, self, held, span) }) };
}

/// Wrap every record construction, record update and `wrap[...]` the
/// current body built since node `first` whose type carries
/// `@invariant`: the value is held in a hidden `self`, each clause is
/// checked against it, and the node yields the held value. The
/// rewrite happens in place, so every parent keeps its reference.
fn enforceInvariants(comptime Checker: type, self: *Checker, first: usize) Error!void {
    if (self.contract.invariants.count() == 0) return;
    const end = self.nodes.items.len;
    var index = first;
    while (index < end) : (index += 1) {
        const node = self.nodes.items[index];
        switch (node.data) {
            .record, .update, .wrap => {},
            else => continue,
        }
        const invariant = self.contract.invariants.get(node.ty) orelse continue;
        const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        const built = try b.node(node.ty, node.data);
        const held = try hiddenLocal(Checker, self, "self", node.ty, node.span);
        var statements: std.ArrayList(typed.StatementId) = .empty;
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = held, .value = built } }));
        const checked_nodes = self.nodes.items.len;
        const checked_statements = self.statements.items.len;
        for (invariant.clauses) |attribute| try statements.append(self.allocator, try invariantStatement(Checker, self, attribute, invariant, held));
        // The check runs where the value was built or changed, so a trap names
        // that site (the clause text rides in its message), and the body keeps
        // no span outside its own declaration.
        for (self.nodes.items[checked_nodes..]) |*checked| checked.span = node.span;
        for (self.statements.items[checked_statements..]) |*checked| checked.span = node.span;
        const body = try b.stmt(.{ .block = try statements.toOwnedSlice(self.allocator) });
        const read = try b.read(held);
        self.nodes.items[index] = .{ .ty = node.ty, .span = node.span, .data = .{ .block_value = .{ .body = body, .value = read } } };
    }
}

/// Reject a parameter named `result` in a function with `@ensures`, where the
/// name means the returned value, and a `result` in a procedure's postcondition,
/// where there is no returned value to name.
fn requireResultName(comptime Checker: type, self: *Checker, function: ast.Function, ensures: []const ast.Attribute) Error!void {
    for (function.signature.parameters) |parameter| if (std.mem.eql(u8, self.src.text(parameter.name), "result"))
        return self.sink.fail(result_code, parameter.name, "in a function with `@ensures`, `result` names the returned value; rename this parameter");
    if (self.return_type != .unit) return;
    for (ensures) |attribute| if (mention(self.syntax, self.src, attribute.condition.?, "result")) |span|
        return self.sink.fail(result_code, span, "this function returns no value, so its `@ensures` clause has no `result` to name");
}

/// A hidden, already-initialized local the checker introduces for a contract.
fn hiddenLocal(comptime Checker: type, self: *Checker, name: []const u8, ty: typed.Type, span: Span) Error!typed.LocalId {
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .name = name,
        .declaration = span,
        .ty = ty,
        .mutable = false,
        .origin = .contract_value,
        .ownership = .{ .initialized = true },
        .usage = .{ .reads = 1, .temporary = true },
    });
    return slot;
}

/// A terminating `return` of one hidden local.
fn returnLocal(comptime Checker: type, self: *Checker, slot: typed.LocalId, span: Span) Error!typed.StatementId {
    const value: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = span, .ty = self.locals.items[@backingInt(slot)].ty, .data = .{ .local = slot } });
    const id: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = .{ .ret = value } });
    return id;
}

/// Check one clause's condition as `bool` in the current scope and return the
/// typed assertion statement that enforces it. The syntax nodes the check
/// resolved are released afterwards, so the same clause can be checked again
/// at another return or construction site.
fn clauseStatement(comptime Checker: type, self: *Checker, clause: Clause) Error!typed.StatementId {
    const condition_id = clause.attribute.condition.?;
    const saved_resolved = self.resolved_nodes.items.len;
    const saved_checking = self.contract.checking;
    self.contract.checking = clause.kind;
    defer self.contract.checking = saved_checking;
    const condition = try self.expressionExpected(condition_id, .bool);
    try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(condition_id)].span);
    for (self.resolved_nodes.items[saved_resolved..]) |index| self.resolved[index] = null;
    self.resolved_nodes.shrinkRetainingCapacity(saved_resolved);
    const note = if (clause.attribute.argument) |literal| try byte_literal.decode(self.allocator, self.src, literal, self.sink) else null;
    const clause_text = self.src.text(self.syntax.nodes.items[@backingInt(condition_id)].span);
    const message = try trapMessage(self.allocator, clause.kind, clause.subject, clause_text, note);
    const id: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = clause.attribute.span, .terminates = false, .data = .{ .assertion = .{ .condition = condition, .message = message, .kind = clause.kind } } });
    return id;
}

/// Check every `@ensures` clause of the current function against `result`
/// (when the function returns a value) in a scope holding only the parameters
/// and `result`, with each `old(...)` bound to its entry capture. Returns the
/// block of assertions.
fn ensuresBlock(comptime Checker: type, self: *Checker, result: ?typed.LocalId, span: Span) Error!typed.StatementId {
    var scope: std.StringHashMapUnmanaged(typed.LocalId) = .empty;
    for (self.locals.items[0..self.contract.parameters], 0..) |local, index| try scope.put(self.allocator, local.name, @fromBackingInt(index));
    if (result) |slot| try scope.put(self.allocator, "result", slot);
    const saved_active = self.active;
    self.active = scope;
    defer self.active = saved_active;
    const facts = try self.option_facts.snapshot(self.allocator);
    self.option_facts.clear();
    defer self.option_facts.restore(facts);
    const saved_resolved = self.resolved_nodes.items.len;
    defer {
        for (self.resolved_nodes.items[saved_resolved..]) |index| self.resolved[index] = null;
        self.resolved_nodes.shrinkRetainingCapacity(saved_resolved);
    }
    for (self.contract.olds) |old| {
        const call = self.syntax.nodes.items[@backingInt(old.node)];
        const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = call.span, .ty = self.locals.items[@backingInt(old.slot)].ty, .data = .{ .local = old.slot } });
        self.resolved[@backingInt(old.node)] = read;
        try self.resolved_nodes.append(self.allocator, @backingInt(old.node));
    }
    var statements: std.ArrayList(typed.StatementId) = .empty;
    for (self.contract.ensures) |attribute| try statements.append(self.allocator, try clauseStatement(Checker, self, .{ .attribute = attribute, .kind = .ensures, .subject = self.contract.subject }));
    const id: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = span, .terminates = false, .data = .{ .block = try statements.toOwnedSlice(self.allocator) } });
    return id;
}

/// Check one `invariant` clause against the hidden `self` holding a value of
/// the carrying type, in a scope holding only `self`. A domain invariant is
/// checked with the domain's own access, so `unwrap(self)` is allowed.
fn invariantStatement(comptime Checker: type, self: *Checker, attribute: ast.Attribute, invariant: Invariant, held: typed.LocalId) Error!typed.StatementId {
    var scope: std.StringHashMapUnmanaged(typed.LocalId) = .empty;
    try scope.put(self.allocator, "self", held);
    const saved_active = self.active;
    self.active = scope;
    defer self.active = saved_active;
    const saved_owner = self.owner;
    if (invariant.domain) self.owner = self.locals.items[@backingInt(held)].ty;
    defer self.owner = saved_owner;
    const facts = try self.option_facts.snapshot(self.allocator);
    self.option_facts.clear();
    defer self.option_facts.restore(facts);
    return clauseStatement(Checker, self, .{ .attribute = attribute, .kind = .invariant, .subject = invariant.name });
}

/// Check the argument of one `old(...)` call in the entry scope and capture it
/// in a hidden local. A value that shares mutable storage with the caller
/// would be observed after the body changed it, so it is rejected unless the
/// expression builds a fresh copy whose elements share nothing.
fn captureOld(comptime Checker: type, self: *Checker, call_id: ast.NodeId) Error!struct { old: Old, statement: typed.StatementId } {
    const call = self.syntax.nodes.items[@backingInt(call_id)];
    const argument = call.data.call.arguments[0];
    const saved_checking = self.contract.checking;
    self.contract.checking = .ensures;
    defer self.contract.checking = saved_checking;
    const value = try self.expression(argument);
    const node = self.nodes.items[@backingInt(value)];
    if (shared(self.catalog.records, node)) {
        const text = self.src.text(self.syntax.nodes.items[@backingInt(argument)].span);
        const type_name = try typed.surfaceTypeName(self.allocator, node.ty, self.catalog.records);
        const message = try std.fmt.allocPrint(
            self.allocator,
            "`old({s})` would see the value after the body changed it, because `{s}` shares storage with the caller; " ++
                "capture a scalar such as `old(len({s}))`, or a fresh copy such as `old({s}.copy())`",
            .{ text, type_name, text, text },
        );
        return self.sink.fail(old_shared_code, call.span, message);
    }
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .name = "<old>",
        .declaration = call.span,
        .ty = node.ty,
        .mutable = false,
        .origin = .contract_old,
        .ownership = .{ .initialized = true },
        .usage = .{ .reads = 1, .temporary = true },
    });
    const id: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = call.span, .terminates = false, .data = .{ .initialize = .{ .slot = slot, .value = value } } });
    return .{ .old = .{ .node = call_id, .slot = slot }, .statement = id };
}

/// Whether capturing this checked value in `old(...)` would alias storage the
/// body can still change: its type shares mutable storage, and it is not a
/// fresh copy whose own elements share none.
fn shared(records: []const typed.Record, node: typed.Node) bool {
    if (!typed.carriesWritableStorage(records, node.ty)) return false;
    if (!fresh(node)) return true;
    const record = records[node.ty.recordIndex()];
    if (!record.isCollection()) return true;
    if (record.collection.key) |key| if (typed.carriesWritableStorage(records, key)) return true;
    return typed.carriesWritableStorage(records, record.shape.buffer.?);
}

/// Whether a checked expression builds a new collection rather than naming an
/// existing one: a literal, a comprehension, or a copying read such as
/// `xs.copy()`, a slice or `d.keys()`. A call is never assumed fresh: its
/// callee may hand back the very list it was given.
fn fresh(node: typed.Node) bool {
    return switch (node.data) {
        .array, .block_value => true,
        .buffer_operation => |operation| switch (operation.kind) {
            .copy, .slice, .slice_step, .keys, .values, .items, .to_list, .split, .splitlines, .split_whitespace => true,
            else => false,
        },
        else => false,
    };
}

//! Contract clauses in the checker. `@requires` conditions are checked at
//! function entry, after the parameters are bound; `@ensures` conditions at
//! every normal return, with `result` naming the returned value and each
//! `old(...)` read from a hidden local captured at entry; `@invariant`
//! conditions wherever a value of the carrying record or domain is built or
//! changed. Each clause is checked as an ordinary Boolean expression and
//! placed in the body as a typed assertion that records its kind, so lowering,
//! both native backends and every cache preserve its kind independently of
//! the message. Codegen selects a dedicated runtime entry for each contract.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const byte_literal = @import("byte_literal.zig");
const collections = @import("collection_lower.zig");
const value_semantics = @import("value_semantics.zig");
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
/// Diagnostic code for `old(x)` of a managed value whose copy is not written `old(copy(x))`.
pub const old_copy_code = "E_CONTRACT_OLD_COPY";

/// One contract trap message: `subject kind `clause`[: message]`. The
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
    if (note) |text| return std.fmt.allocPrint(allocator, "{s} {s} `{s}`: {s}", .{ subject, word, folded.items, text });
    return std.fmt.allocPrint(allocator, "{s} {s} `{s}`", .{ subject, word, folded.items });
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

/// The Boolean, message and span of one clause, ready to check. `context`
/// explains a clause checked away from its own declaration: an invariant a
/// test checks on a parameter the harness supplied.
/// `write` is a clause checked after a field write, a write in place or a write through a `match mut` binding: its trap
/// says the fields the invariant relates can be written together with `replace(...)` (`writeHint`).
const Clause = struct { attribute: ast.Attribute, kind: typed.AssertionKind, subject: []const u8, context: ?[]const u8 = null, write: bool = false };

/// Where an invariant clause is checked: against the hidden `self` that `held` is, and whether a write put the value there.
const Site = struct { held: typed.LocalId, write: bool = false };

/// Bind contract checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Index every record and domain carrying `@invariant` by its checked type.
        pub fn indexInvariants(self: *Checker) Error!void {
            return impl.indexInvariants(Checker, self);
        }
        /// Compile each declared invariant for use by decoded-value boundaries.
        pub fn boundaryValidators(self: *Checker) Error![]typed.Function {
            return impl.boundaryValidators(Checker, self);
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
        /// Check `@invariant` wherever the current body, from node `first` and statement
        /// `first_statement` on, built or changed a carrying value.
        pub fn enforceInvariants(self: *Checker, first: usize, first_statement: usize) Error!void {
            return impl.enforceInvariants(Checker, self, first, first_statement);
        }
        /// The places the expression `id` writes in place (a field's `take` or `exchange`, a collection update through a
        /// receiver rooted at a field, a `mut` argument that is a field), at most `out.len`; the `@sealed` rules read them.
        pub fn writtenPlaces(self: *Checker, id: typed.NodeId, out: *[8]typed.NodeId) usize {
            return impl.writtenPlaces(Checker, self, id, out);
        }
    };
}
const impl = @This();

/// Build callbacks independently of ordinary bodies. Their final function IDs
/// are assigned after any generic calls their clauses instantiate are checked.
fn boundaryValidators(comptime Checker: type, self: *Checker) Error![]typed.Function {
    var functions: std.ArrayList(typed.Function) = .empty;
    // Catalog order makes callback identities and manifests deterministic.
    const count = self.catalog.records.len;
    for (0..count) |index| {
        const ty: typed.Type = @fromBackingInt(index + typed.Type.record_base);
        const invariant = self.contract.invariants.get(ty) orelse continue;
        try functions.append(self.allocator, try boundaryValidator(Checker, self, ty, invariant));
    }
    return functions.toOwnedSlice(self.allocator);
}

/// Clear the checker's per-body state before it checks the body of a compiler-made function (a boundary validator, or a
/// field default's builder for `json.decode`, `codec_defaults.zig`).
pub fn resetSynthetic(comptime Checker: type, self: *Checker) void {
    self.current_function = null;
    self.current_lambda = null;
    for (self.resolved_nodes.items) |node| self.resolved.put(node, null);
    self.resolved_nodes.clearRetainingCapacity();
    self.expected_types.clearRetainingCapacity();
    self.option_facts.clear();
    self.locals = .empty;
    self.consuming_bindings.clearRetainingCapacity();
    self.match_lent_owners.clearRetainingCapacity();
    self.active.clearRetainingCapacity();
    self.owner = null;
    self.return_type = .i64;
    self.conversion_fields = null;
    self.contract.ensures = &.{};
    self.contract.olds = &.{};
}

fn boundaryValidator(comptime Checker: type, self: *Checker, ty: typed.Type, invariant: Invariant) Error!typed.Function {
    resetSynthetic(Checker, self);
    const record = self.catalog.records[ty.recordIndex()];
    const held = try hiddenLocal(Checker, self, "self", ty, record.declaration);
    self.locals.items[@backingInt(held)].origin = .parameter;
    var statements: std.ArrayList(typed.StatementId) = .empty;
    for (invariant.clauses) |attribute| try statements.append(self.allocator, try invariantStatement(Checker, self, attribute, invariant, .{ .held = held }));
    const b: collections.Builder(Checker) = .{ .checker = self, .span = record.declaration };
    try statements.append(self.allocator, try b.stmt(.{ .ret = try b.integer(0) }));
    const body = try b.stmt(.{ .block = try statements.toOwnedSlice(self.allocator) });
    self.statements.items[@backingInt(body)].terminates = true;
    return .{
        .id = @fromBackingInt(0),
        .name = try @import("invariant_callbacks.zig").functionName(self.allocator, record.name),
        .policy = .{ .owner = if (invariant.domain) ty else null },
        .declaration = record.declaration,
        .signature = .{ .return_type = .i64, .parameter_count = 1 },
        .scope = .{ .body_complete = true, .body = body, .locals = try self.locals.toOwnedSlice(self.allocator) },
    };
}

/// The prefix of a record's invariant test for `json.decode`, `@holds:Record`: it answers 1 when every clause holds.
pub const holds_prefix = "@holds:";

/// The function that tests the `@invariant` clauses of the record `ty` without trapping (CODEC-INV, 17 November 2026):
/// `json.decode` fails with kind `invariant` when it answers 0. Null for a type that carries none, and for a domain.
pub fn invariantTest(comptime Checker: type, self: *Checker, ty: typed.Type) Error!?typed.Function {
    const invariant = self.contract.invariants.get(ty) orelse return null;
    if (invariant.domain) return null;
    resetSynthetic(Checker, self);
    const record = self.catalog.records[ty.recordIndex()];
    const held = try hiddenLocal(Checker, self, "self", ty, record.declaration);
    self.locals.items[@backingInt(held)].origin = .parameter;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = record.declaration };
    var statements: std.ArrayList(typed.StatementId) = .empty;
    for (invariant.clauses) |attribute| {
        const condition = try holdsCondition(Checker, self, attribute, held);
        const keep = try b.stmt(.{ .block = &.{} });
        const leave = try b.stmt(.{ .ret = try b.integer(0) });
        self.statements.items[@backingInt(leave)].terminates = true;
        try statements.append(self.allocator, try b.stmt(.{ .branch = .{ .condition = condition, .then_body = keep, .else_body = leave } }));
    }
    try statements.append(self.allocator, try b.stmt(.{ .ret = try b.integer(1) }));
    const body = try b.stmt(.{ .block = try statements.toOwnedSlice(self.allocator) });
    self.statements.items[@backingInt(body)].terminates = true;
    return .{
        .id = @fromBackingInt(0),
        .name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ holds_prefix, record.name }),
        .declaration = record.declaration,
        .signature = .{ .return_type = .i64, .parameter_count = 1 },
        .scope = .{ .body_complete = true, .body = body, .locals = try self.locals.toOwnedSlice(self.allocator) },
    };
}

/// One invariant clause's condition, checked as a Boolean over the hidden `self` that `held` is, as `invariantStatement`
/// checks it for its trap.
fn holdsCondition(comptime Checker: type, self: *Checker, attribute: ast.Attribute, held: typed.LocalId) Error!typed.NodeId {
    var scope: std.StringHashMapUnmanaged(typed.LocalId) = .empty;
    try scope.put(self.allocator, "self", held);
    const saved_active = self.active;
    self.active = scope;
    defer self.active = saved_active;
    const saved_checking = self.contract.checking;
    self.contract.checking = .invariant;
    defer self.contract.checking = saved_checking;
    const saved_resolved = self.resolved_nodes.items.len;
    const condition_id = attribute.condition.?;
    const condition = try self.expressionExpected(condition_id, .bool);
    try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(condition_id)].span);
    for (self.resolved_nodes.items[saved_resolved..]) |index| self.resolved.put(index, null);
    self.resolved_nodes.shrinkRetainingCapacity(saved_resolved);
    return condition;
}

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
    const subject = if (function.policy.owner) |owner|
        try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.src.text(owner), self.src.text(function.name) })
    else
        self.src.text(function.name);
    const harness = try harnessPrologue(Checker, self, function, subject, attributes);
    if (!any) return harness;
    self.contract.subject = subject;
    self.contract.parameters = function.signature.parameters.len;
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.appendSlice(self.allocator, harness);
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
        const dispatch = try b.stmt(.{ .match = .{ .value = try b.read(held), .arms = arms, .borrowed = true } });
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

/// Check after its write every field store the current body made since
/// statement `first_statement`, then wrap every other record construction,
/// record update and `wrap[...]` it built since node `first` whose type carries
/// `@invariant`: the value is held in a hidden `self`, each clause is
/// checked against it, and the node yields the held value. The
/// rewrite happens in place, so every parent keeps its reference.
fn enforceInvariants(comptime Checker: type, self: *Checker, first: usize, first_statement: usize) Error!void {
    if (self.contract.invariants.count() == 0) return;
    const end = self.nodes.items.len;
    // A field store is checked after its write, against the place it wrote
    // (`checkAfterStore`); its updates are not wrapped again below.
    var stored: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer stored.deinit(self.allocator);
    const statement_end = self.statements.items.len;
    var statement = first_statement;
    while (statement < statement_end) : (statement += 1) try checkAfterStore(Checker, self, .{ .id = statement, .first = first_statement }, &stored);
    // A place written in place (`take`, `exchange`, a collection update or a
    // `mut` argument, on a field) is checked after its write the same way
    // (`checkAfterPlaceWrite`); the nodes it rewrites build no record.
    var written = first;
    while (written < end) : (written += 1) try checkAfterPlaceWrite(Checker, self, written);
    // A write through a `match mut` payload binding changes the record the matched place lies in, which no check above
    // sees: the binding is the store's root (FX7b).
    try checkAfterBindingWrites(Checker, self, first, first_statement);
    var index = first;
    while (index < end) : (index += 1) {
        const node = self.nodes.items[index];
        switch (node.data) {
            .record, .update, .wrap => {},
            else => continue,
        }
        if (stored.contains(index)) continue;
        const invariant = self.contract.invariants.get(node.ty) orelse continue;
        const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        const built = try b.node(node.ty, node.data);
        const held = try hiddenLocal(Checker, self, "self", node.ty, node.span);
        var statements: std.ArrayList(typed.StatementId) = .empty;
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = held, .value = built } }));
        const checked_nodes = self.nodes.items.len;
        const checked_statements = self.statements.items.len;
        const checked_locals = self.locals.items.len;
        for (invariant.clauses) |attribute| try statements.append(self.allocator, try invariantStatement(Checker, self, attribute, invariant, .{ .held = held }));
        // The check runs where the value was built or changed, so a trap names
        // that site (the clause text rides in its message), and the body keeps
        // no span outside its own declaration.
        relocateChecks(self.nodes.items[checked_nodes..], self.statements.items[checked_statements..], self.locals.items[checked_locals..], node.span);
        const body = try b.stmt(.{ .block = try statements.toOwnedSlice(self.allocator) });
        const read = try b.read(held);
        self.nodes.items[index] = .{ .ty = node.ty, .span = node.span, .data = .{ .block_value = .{ .body = body, .value = read } } };
    }
}

/// How deep a field store's chain of updates (`t.a.b.c = v`) is followed.
const store_depth = 16;

/// One statement of the body being checked, and the body's first statement.
const StoreAt = struct { id: usize, first: usize };

/// What every initialization of the receiver `owner` among `statements` reads:
/// a whole local (the receiver is that local's own storage), or one field of
/// a whole local (`h.rows`), which is written back into it after the store.
const OwnerRoot = union(enum) { whole, field: struct { slot: typed.LocalId, index: usize } };

fn ownerRoot(statements: []const typed.Statement, nodes: []const typed.Node, owner: typed.LocalId) ?OwnerRoot {
    var found: ?OwnerRoot = null;
    for (statements) |statement| switch (statement.data) {
        .initialize => |store| if (store.slot == owner) {
            const this: OwnerRoot = switch (nodes[@backingInt(store.value)].data) {
                .local => .whole,
                .field => |field| switch (nodes[@backingInt(field.base)].data) {
                    .local => |slot| .{ .field = .{ .slot = slot, .index = field.index } },
                    else => return null,
                },
                else => return null,
            };
            if (found) |seen| if (!std.meta.eql(seen, this)) return null;
            found = this;
        },
        else => {},
    };
    return found;
}

/// Where a field store's value lands, read back after the write: a named
/// local (a parameter, a local, a `match mut` binding), the case of a narrowed
/// option local (`o.f = v` after `o is not None` stores `Some(...)`), or a list
/// or dictionary element written through a receiver rooted at a local or at
/// one of its fields.
const StoreRoot = union(enum) {
    local: typed.LocalId,
    case: struct { slot: typed.LocalId, tag: usize },
    element: struct { owner: typed.LocalId, index: typed.LocalId, rooted: OwnerRoot },
};

/// A field store (`t.f = v`, `t.inner.x = v`, `xs[i].f = v`, a `match mut`
/// binding's `r.f = v`) writes one record update into its place. Wrapping that
/// update in a hidden `self` would move the place's value out of it, which a
/// `mut` parameter or an element cannot lend (rule M1). So the store stays as
/// it is and every invariant on its chain of updates is checked after the
/// write, innermost first, against the place itself, read through borrowed
/// hidden locals: no record is copied. The statement is rewritten in place.
fn checkAfterStore(comptime Checker: type, self: *Checker, at: StoreAt, stored: *std.AutoHashMapUnmanaged(usize, void)) Error!void {
    const statement = self.statements.items[at.id];
    var top: typed.NodeId = undefined;
    const root: StoreRoot = switch (statement.data) {
        .assign => |store| root: {
            // A hidden receiver is written back into its own root afterwards.
            const name = self.locals.items[@backingInt(store.slot)].name;
            if (name.len == 0 or name[0] == '<') return;
            top = store.value;
            switch (self.nodes.items[@backingInt(top)].data) {
                .variant => |variant| {
                    top = variant.value orelse return;
                    break :root .{ .case = .{ .slot = store.slot, .tag = variant.tag } };
                },
                else => break :root .{ .local = store.slot },
            }
        },
        .discard => |value| root: {
            const operation = switch (self.nodes.items[@backingInt(value)].data) {
                .buffer_operation => |operation| operation,
                else => return,
            };
            if (operation.kind != .write or operation.arguments.len != 2) return;
            const index_slot = switch (self.nodes.items[@backingInt(operation.arguments[0])].data) {
                .local => |slot| slot,
                else => return,
            };
            const rooted = ownerRoot(self.statements.items[at.first..at.id], self.nodes.items, operation.owner) orelse return;
            top = operation.arguments[1];
            break :root .{ .element = .{ .owner = operation.owner, .index = index_slot, .rooted = rooted } };
        },
        else => return,
    };
    // The chain of field updates and fixed-array element replacements the
    // store builds, outermost first.
    var levels: [store_depth]typed.NodeId = undefined;
    var count: usize = 0;
    var deepest: ?usize = null;
    var current = top;
    while (count < store_depth) {
        const node = self.nodes.items[@backingInt(current)];
        switch (node.data) {
            .update => |update| {
                levels[count] = current;
                if (self.contract.invariants.contains(node.ty)) deepest = count;
                count += 1;
                if (update.fields.len != 1) break;
                current = update.fields[0].value;
            },
            .replace => |replace| {
                if (!reusableKey(self.nodes.items[@backingInt(replace.index)])) break;
                levels[count] = current;
                count += 1;
                current = replace.value;
            },
            else => break,
        }
    }
    const last = deepest orelse return;
    const span = self.nodes.items[@backingInt(levels[0])].span;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const checked_nodes = self.nodes.items.len;
    const checked_statements = self.statements.items.len;
    const checked_locals = self.locals.items.len;
    var checks: std.ArrayList(typed.StatementId) = .empty;
    // The borrowed holder of the outermost level: the root itself, or a hidden
    // `self` read from it; `checkLevels` reads each deeper level from it.
    var holders: [1]typed.LocalId = undefined;
    const top_type = self.nodes.items[@backingInt(levels[0])].ty;
    switch (root) {
        .local => |slot| holders[0] = slot,
        .case => holders[0] = try hiddenLocal(Checker, self, "self", top_type, span),
        .element => |written| {
            holders[0] = try hiddenLocal(Checker, self, "self", top_type, span);
            // A receiver rooted at a field is written back into its record after
            // the store, so the element is read again through a new borrow of it.
            const owner = switch (written.rooted) {
                .whole => written.owner,
                .field => |field| owner: {
                    const ty = self.locals.items[@backingInt(written.owner)].ty;
                    const again = try b.local(ty);
                    const value = try b.node(ty, .{ .field = .{ .base = try b.read(field.slot), .index = field.index } });
                    try checks.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = again, .value = value } }));
                    break :owner again;
                },
            };
            const read = try b.operation(owner, .read, &.{try b.read(written.index)});
            try checks.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = holders[0], .value = read } }));
        },
    }
    var chain: [store_depth]Level = undefined;
    for (levels[0 .. last + 1], chain[0 .. last + 1]) |id, *level| {
        const node = self.nodes.items[@backingInt(id)];
        level.* = .{ .ty = node.ty, .step = switch (node.data) {
            .update => |update| .{ .field = update.fields[0].index },
            .replace => |replace| .{ .key = replace.index },
            else => unreachable,
        } };
    }
    try checkLevels(Checker, self, b, holders[0], chain[0 .. last + 1], &checks);
    if (root == .case) {
        // Read the stored case back through a borrowed match on the option.
        const case = root.case;
        const cases = self.catalog.records[self.locals.items[@backingInt(case.slot)].ty.recordIndex()].shape.variants.?.cases;
        const arms = try self.allocator.alloc(typed.MatchArm, cases.len);
        const body = try b.stmt(.{ .block = try checks.toOwnedSlice(self.allocator) });
        for (arms, 0..) |*arm, tag| arm.* = if (tag == case.tag)
            .{ .tag = tag, .slot = holders[0], .body = body }
        else
            .{ .tag = tag, .slot = null, .body = try b.stmt(.{ .block = &.{} }) };
        try checks.append(self.allocator, try b.stmt(.{ .match = .{ .value = try b.read(case.slot), .arms = arms, .borrowed = true } }));
    }
    relocateChecks(self.nodes.items[checked_nodes..], self.statements.items[checked_statements..], self.locals.items[checked_locals..], span);
    for (levels[0..count]) |node| try stored.put(self.allocator, @backingInt(node), {});
    // The write keeps its own statement, now first in the block that replaces it.
    const write: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = statement.span, .terminates = false, .data = statement.data });
    try checks.insert(self.allocator, 0, write);
    self.statements.items[at.id] = .{ .span = statement.span, .terminates = statement.terminates, .data = .{ .block = try checks.toOwnedSlice(self.allocator) } };
}

/// One record on the path from a written place's root to the write, root
/// first: its type, and how the next level is read from it (a field, or a
/// fixed-array element under a key that can be read again).
const Level = struct { ty: typed.Type, step: union(enum) { field: usize, key: typed.NodeId } };

/// Check every invariant of `levels` after a write, innermost first, against
/// the place itself: `root` holds the first level, and each deeper level is
/// read from the one above into a borrowed hidden `self`. No record is copied.
fn checkLevels(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), root: typed.LocalId, levels: []const Level, checks: *std.ArrayList(typed.StatementId)) Error!void {
    var holders: [store_depth]typed.LocalId = undefined;
    holders[0] = root;
    for (1..levels.len) |level| {
        const ty = levels[level].ty;
        const base = try b.read(holders[level - 1]);
        const value = switch (levels[level - 1].step) {
            .field => |index| try b.node(ty, .{ .field = .{ .base = base, .index = index } }),
            .key => |key| try b.node(ty, .{ .index = .{ .base = base, .index = try reuseKey(Checker, self, b, key) } }),
        };
        holders[level] = try hiddenLocal(Checker, self, "self", ty, b.span);
        try checks.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = holders[level], .value = value } }));
    }
    var level = levels.len;
    while (level > 0) {
        level -= 1;
        const invariant = self.contract.invariants.get(levels[level].ty) orelse continue;
        for (invariant.clauses) |attribute| try checks.append(self.allocator, try invariantStatement(Checker, self, attribute, invariant, .{ .held = holders[level], .write = true }));
    }
}

/// Where a place written in place starts: a named local (a parameter, a local
/// or a `match mut` binding), or a list element `xs[i]` or `h.rows[i]`, read
/// again after the write through a new receiver of `list` (a local, or one
/// field of a local) under the same `index`.
const PlaceRoot = union(enum) {
    local: typed.LocalId,
    element: struct { list: typed.NodeId, index: typed.NodeId, ty: typed.Type },
};

/// A place written in place, from its root to the write: the root and the
/// records on the way, root first.
const PlacePath = struct { root: PlaceRoot, levels: [store_depth]Level, count: usize };

/// The path of a place a `take`, an `exchange`, a collection update or a
/// `mut` argument writes in place: a chain of record fields (and fixed-array
/// elements under a key that can be read again) ending at a named local or a
/// list element. Null for a whole local, whose new value was built (and checked)
/// where it was made, and for any other place, which is left as it was.
fn placePath(comptime Checker: type, self: *Checker, place: typed.NodeId) ?PlacePath {
    const nodes = self.nodes.items;
    var out: PlacePath = .{ .root = undefined, .levels = undefined, .count = 0 };
    var current = place;
    while (true) {
        const node = nodes[@backingInt(current)];
        const base = switch (node.data) {
            .field => |field| field.base,
            .index => |index| if (reusableKey(nodes[@backingInt(index.index)])) index.base else return null,
            .local => |slot| {
                if (out.count == 0 or hidden(self.locals.items[@backingInt(slot)].name)) return null;
                out.root = .{ .local = slot };
                break;
            },
            .block_value => {
                out.root = .{ .element = elementRead(Checker, self, current) orelse return null };
                break;
            },
            else => return null,
        };
        if (out.count == store_depth) return null;
        out.levels[out.count] = .{ .ty = nodes[@backingInt(base)].ty, .step = switch (node.data) {
            .field => |field| .{ .field = field.index },
            .index => |index| .{ .key = index.index },
            else => unreachable,
        } };
        out.count += 1;
        current = base;
    }
    std.mem.reverse(Level, out.levels[0..out.count]);
    return out;
}

/// A compiler temporary, which aliases some other place (`<collection>`).
fn hidden(name: []const u8) bool {
    return name.len == 0 or name[0] == '<';
}

/// A list element read `xs[i]` as the checker builds it: a block that roots a
/// receiver from a local (or one field of a local) and reads under a key that
/// can be read again.
fn elementRead(comptime Checker: type, self: *Checker, id: typed.NodeId) ?@FieldType(PlaceRoot, "element") {
    const nodes = self.nodes.items;
    const block = nodes[@backingInt(id)].data.block_value;
    const read = switch (nodes[@backingInt(block.value)].data) {
        .buffer_operation => |operation| operation,
        else => return null,
    };
    if (read.kind != .read or read.arguments.len != 1 or !reusableKey(nodes[@backingInt(read.arguments[0])])) return null;
    const list = receiverSource(Checker, self, block.body, read.owner) orelse return null;
    switch (nodes[@backingInt(list)].data) {
        .local => |slot| if (hidden(self.locals.items[@backingInt(slot)].name)) return null,
        .field => |field| switch (nodes[@backingInt(field.base)].data) {
            .local => |slot| if (hidden(self.locals.items[@backingInt(slot)].name)) return null,
            else => return null,
        },
        else => return null,
    }
    return .{ .list = list, .index = read.arguments[0], .ty = nodes[@backingInt(id)].ty };
}

/// The value the block `body` initializes the receiver `owner` from, when it
/// does so once among its own statements.
fn receiverSource(comptime Checker: type, self: *Checker, body: typed.StatementId, owner: typed.LocalId) ?typed.NodeId {
    const statements = switch (self.statements.items[@backingInt(body)].data) {
        .block => |statements| statements,
        else => return null,
    };
    var found: ?typed.NodeId = null;
    for (statements) |id| switch (self.statements.items[@backingInt(id)].data) {
        .initialize => |store| if (store.slot == owner) {
            if (found != null) return null;
            found = store.value;
        },
        else => {},
    };
    return found;
}

/// Whether the block `body` writes through the receiver `owner`: an updating
/// collection operation on it, or a `take`/`exchange` of it, as one of its
/// statements (looking into the blocks a checked store became) or as `value`.
fn writesReceiver(comptime Checker: type, self: *Checker, body: typed.StatementId, value: typed.NodeId, owner: typed.LocalId) bool {
    if (writesThrough(self.nodes.items, value, owner)) return true;
    return statementWrites(Checker, self, body, owner, 0);
}

fn statementWrites(comptime Checker: type, self: *Checker, id: typed.StatementId, owner: typed.LocalId, depth: usize) bool {
    if (depth == store_depth) return false;
    return switch (self.statements.items[@backingInt(id)].data) {
        .block => |statements| for (statements) |child| {
            if (statementWrites(Checker, self, child, owner, depth + 1)) break true;
        } else false,
        .discard => |value| writesThrough(self.nodes.items, value, owner),
        else => false,
    };
}

fn writesThrough(nodes: []const typed.Node, id: typed.NodeId, owner: typed.LocalId) bool {
    return switch (nodes[@backingInt(id)].data) {
        .buffer_operation => |operation| operation.owner == owner and operation.kind.mutates(),
        .place_exchange => |exchange| switch (nodes[@backingInt(exchange.place)].data) {
            .local => |slot| slot == owner,
            else => false,
        },
        else => false,
    };
}

/// Whether a node can name a part of a record or list (a field, an element):
/// `placePath` decides whether it does.
fn placeLike(node: typed.Node) bool {
    return switch (node.data) {
        .field, .index, .block_value => true,
        else => false,
    };
}

/// How many places one expression writes in place.
const max_written = 8;

/// The places the expression `id` writes in place, outside a field store:
/// `take(mut t.f)` and `exchange(mut t.f, v)`; a block that writes through a
/// receiver it roots at a field (`append(mut t.items, v)`, `t.items[i] = v`,
/// `t.map[k] = v`, `h.rows[i].f = v`, an element's `take`); and the `mut`
/// arguments that are fields of a call or a callback's invocation
/// (`f(mut t.items)`, `lists.pop(mut t.items)`, `hook(mut t.items)`).
pub fn writtenPlaces(comptime Checker: type, self: *Checker, id: typed.NodeId, out: *[max_written]typed.NodeId) usize {
    const nodes = self.nodes.items;
    var count: usize = 0;
    switch (nodes[@backingInt(id)].data) {
        .place_exchange => |exchange| if (nodes[@backingInt(exchange.place)].data != .local) {
            out[0] = exchange.place;
            count = 1;
        },
        .block_value => |block| {
            const statements = switch (self.statements.items[@backingInt(block.body)].data) {
                .block => |statements| statements,
                else => return 0,
            };
            for (statements) |statement| switch (self.statements.items[@backingInt(statement)].data) {
                .initialize => |store| {
                    if (count == max_written) break;
                    if (!hidden(self.locals.items[@backingInt(store.slot)].name)) continue;
                    if (!placeLike(nodes[@backingInt(store.value)])) continue;
                    if (!writesReceiver(Checker, self, block.body, block.value, store.slot)) continue;
                    out[count] = store.value;
                    count += 1;
                },
                else => {},
            };
        },
        .call => |call| {
            if (@backingInt(call.function) >= self.instance_keys.items.len) return 0;
            return mutArguments(self.syntaxFunction(call.function).signature.mut_positions, call.arguments, nodes, out);
        },
        .invoke => |call| {
            const callee = nodes[@backingInt(call.callee)].ty;
            if (!callee.isAggregate()) return 0;
            const callback = self.catalog.records[callee.recordIndex()].contract.callback orelse return 0;
            return mutArguments(callback.mutates, call.arguments, nodes, out);
        },
        else => {},
    }
    return count;
}

/// The arguments at a callee's `mut` positions that can name a part of a
/// record or list.
fn mutArguments(mutates: []const u16, arguments: []const typed.NodeId, nodes: []const typed.Node, out: *[max_written]typed.NodeId) usize {
    var count: usize = 0;
    for (mutates) |position| {
        if (count == max_written or position >= arguments.len) break;
        const argument = arguments[position];
        if (!placeLike(nodes[@backingInt(argument)])) continue;
        out[count] = argument;
        count += 1;
    }
    return count;
}

/// A place written in place (`take`, `exchange`, a collection update or a call
/// with a `mut` argument, on a field) changes every record on its path without
/// a record update, so no store check sees it. The expression is kept, its
/// value is held in a hidden local, and every invariant on each path is
/// checked after it, innermost first, against the place itself through
/// borrowed reads: no record is copied. The node is rewritten in place.
fn checkAfterPlaceWrite(comptime Checker: type, self: *Checker, index: usize) Error!void {
    var places: [max_written]typed.NodeId = undefined;
    const count = writtenPlaces(Checker, self, @fromBackingInt(index), &places);
    if (count == 0) return;
    var paths: [max_written]PlacePath = undefined;
    var checked: usize = 0;
    for (places[0..count]) |place| {
        const path = placePath(Checker, self, place) orelse continue;
        if (!carriesOnPath(Checker, self, path)) continue;
        paths[checked] = path;
        checked += 1;
    }
    if (checked == 0) return;
    const node = self.nodes.items[index];
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const write = try b.node(node.ty, node.data);
    const checked_nodes = self.nodes.items.len;
    const checked_statements = self.statements.items.len;
    const checked_locals = self.locals.items.len;
    var statements: std.ArrayList(typed.StatementId) = .empty;
    // A `Unit` write is discarded; any other value is held and yielded after the checks.
    const held: ?typed.LocalId = if (node.ty == .unit) null else try hiddenLocal(Checker, self, "self", node.ty, node.span);
    try statements.append(self.allocator, try b.stmt(if (held) |slot| .{ .initialize = .{ .slot = slot, .value = write } } else .{ .discard = write }));
    for (paths[0..checked]) |path| try checkPath(Checker, self, b, path, &statements);
    relocateChecks(self.nodes.items[checked_nodes..], self.statements.items[checked_statements..], self.locals.items[checked_locals..], node.span);
    const body = try b.stmt(.{ .block = try statements.toOwnedSlice(self.allocator) });
    const value = if (held) |slot| try b.read(slot) else try b.node(.unit, .unit);
    self.nodes.items[index] = .{ .ty = node.ty, .span = node.span, .data = .{ .block_value = .{ .body = body, .value = value } } };
}

/// Whether a record on `path` carries an invariant: one of its levels, or the
/// record whose field holds the list an element root reads.
fn carriesOnPath(comptime Checker: type, self: *Checker, path: PlacePath) bool {
    for (path.levels[0..path.count]) |level| if (self.contract.invariants.contains(level.ty)) return true;
    return if (listOwner(Checker, self, path.root)) |slot| self.contract.invariants.contains(self.locals.items[@backingInt(slot)].ty) else false;
}

/// The local whose field holds the list an element root reads (`h` of `h.rows[i]`).
fn listOwner(comptime Checker: type, self: *Checker, root: PlaceRoot) ?typed.LocalId {
    const element = switch (root) {
        .element => |element| element,
        .local => return null,
    };
    return switch (self.nodes.items[@backingInt(element.list)].data) {
        .field => |field| self.nodes.items[@backingInt(field.base)].data.local,
        else => null,
    };
}

/// Append the checks of every invariant on one written path, innermost first:
/// the levels down to the deepest record that carries one, then the record
/// that holds an element root's list.
fn checkPath(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), path: PlacePath, checks: *std.ArrayList(typed.StatementId)) Error!void {
    var deepest: ?usize = null;
    for (path.levels[0..path.count], 0..) |level, at| if (self.contract.invariants.contains(level.ty)) {
        deepest = at;
    };
    if (deepest) |last| {
        const root = switch (path.root) {
            .local => |slot| slot,
            .element => |element| root: {
                // The list is rooted again through a new receiver, and the element read under the same key.
                const list = self.nodes.items[@backingInt(element.list)];
                const again = try b.local(list.ty);
                const source_value = switch (list.data) {
                    .local => |slot| try b.read(slot),
                    .field => |field| try b.node(list.ty, .{ .field = .{ .base = try b.read(self.nodes.items[@backingInt(field.base)].data.local), .index = field.index } }),
                    else => unreachable,
                };
                try checks.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = again, .value = source_value } }));
                const holder = try hiddenLocal(Checker, self, "self", element.ty, b.span);
                const read = try b.operation(again, .read, &.{try reuseKey(Checker, self, b, element.index)});
                try checks.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = holder, .value = read } }));
                break :root holder;
            },
        };
        try checkLevels(Checker, self, b, root, path.levels[0 .. last + 1], checks);
    }
    const owner = listOwner(Checker, self, path.root) orelse return;
    const invariant = self.contract.invariants.get(self.locals.items[@backingInt(owner)].ty) orelse return;
    for (invariant.clauses) |attribute| try checks.append(self.allocator, try invariantStatement(Checker, self, attribute, invariant, .{ .held = owner, .write = true }));
}

/// A `match mut` payload binding, or a named field of one (`case on(pair=p):` binds `p` from the payload), and the place
/// the match writes into (FX7b).
const Binding = struct { slot: typed.LocalId, place: typed.NodeId };

/// The bindings of every `match mut` of the body since `first_statement`, and the named locals made from a field of one.
fn collectBindings(comptime Checker: type, self: *Checker, first_statement: usize) Error![]const Binding {
    var found: std.ArrayList(Binding) = .empty;
    for (self.statements.items[first_statement..]) |statement| switch (statement.data) {
        .match => |match| if (match.exclusive) for (match.arms) |arm| {
            if (arm.slot) |slot| try found.append(self.allocator, .{ .slot = slot, .place = match.value });
            if (arm.unpack) |unpack| for (unpack.fields) |field| if (field) |slot| try found.append(self.allocator, .{ .slot = slot, .place = match.value });
        },
        else => {},
    };
    if (found.items.len == 0) return found.items;
    // A named field binding is initialized from a field of the payload binding; follow chains of them.
    var changed = true;
    while (changed) {
        changed = false;
        for (self.statements.items[first_statement..]) |statement| switch (statement.data) {
            .initialize => |store| {
                if (hidden(self.locals.items[@backingInt(store.slot)].name) or bindingPlace(found.items, store.slot) != null) continue;
                const root = fieldRoot(self.nodes.items, store.value) orelse continue;
                const place = bindingPlace(found.items, root) orelse continue;
                try found.append(self.allocator, .{ .slot = store.slot, .place = place });
                changed = true;
            },
            else => {},
        };
    }
    return found.items;
}

/// The place the binding `slot` writes into, or null when it is no `match mut` binding.
fn bindingPlace(bindings: []const Binding, slot: typed.LocalId) ?typed.NodeId {
    for (bindings) |binding| if (binding.slot == slot) return binding.place;
    return null;
}

/// The local a chain of field reads starts at (`p.a.b` gives `p`), or null.
fn fieldRoot(nodes: []const typed.Node, id: typed.NodeId) ?typed.LocalId {
    var current = id;
    while (true) switch (nodes[@backingInt(current)].data) {
        .field => |field| current = field.base,
        .local => |slot| return slot,
        else => return null,
    };
}

/// The local a place starts at: through fields, fixed-array elements and a list element's receiver.
fn placeRoot(comptime Checker: type, self: *Checker, id: typed.NodeId) ?typed.LocalId {
    var current = id;
    for (0..store_depth) |_| switch (self.nodes.items[@backingInt(current)].data) {
        .field => |field| current = field.base,
        .index => |index| current = index.base,
        .local => |slot| return slot,
        .block_value => current = (elementRead(Checker, self, current) orelse return null).list,
        else => return null,
    };
    return null;
}

/// The `match mut` bindings the expression `id` writes in place: a `take` or `exchange` of a part of one, a block that
/// writes through a receiver rooted at one (`append(mut xs, v)`), and the `mut` arguments rooted at one (`bump(mut v)`).
fn writtenBindings(comptime Checker: type, self: *Checker, bindings: []const Binding, id: typed.NodeId, out: *[max_written]typed.LocalId) usize {
    const nodes = self.nodes.items;
    var places: [max_written]typed.NodeId = undefined;
    var count: usize = 0;
    switch (nodes[@backingInt(id)].data) {
        .place_exchange => |exchange| {
            places[0] = exchange.place;
            count = 1;
        },
        .block_value => |block| {
            const statements = switch (self.statements.items[@backingInt(block.body)].data) {
                .block => |statements| statements,
                else => return 0,
            };
            for (statements) |statement| switch (self.statements.items[@backingInt(statement)].data) {
                .initialize => |store| {
                    if (count == max_written) break;
                    if (!hidden(self.locals.items[@backingInt(store.slot)].name)) continue;
                    if (!writesReceiver(Checker, self, block.body, block.value, store.slot)) continue;
                    places[count] = store.value;
                    count += 1;
                },
                else => {},
            };
        },
        .call => |call| {
            if (@backingInt(call.function) >= self.instance_keys.items.len) return 0;
            count = everyMutArgument(self.syntaxFunction(call.function).signature.mut_positions, call.arguments, &places);
        },
        .invoke => |call| {
            const callee = nodes[@backingInt(call.callee)].ty;
            if (!callee.isAggregate()) return 0;
            const callback = self.catalog.records[callee.recordIndex()].contract.callback orelse return 0;
            count = everyMutArgument(callback.mutates, call.arguments, &places);
        },
        else => return 0,
    }
    var written: usize = 0;
    for (places[0..count]) |place| {
        const root = placeRoot(Checker, self, place) orelse continue;
        if (bindingPlace(bindings, root) == null) continue;
        out[written] = root;
        written += 1;
    }
    return written;
}

/// The arguments at a callee's `mut` positions, whatever they name.
fn everyMutArgument(mutates: []const u16, arguments: []const typed.NodeId, out: *[max_written]typed.NodeId) usize {
    var count: usize = 0;
    for (mutates) |position| {
        if (count == max_written or position >= arguments.len) break;
        out[count] = arguments[position];
        count += 1;
    }
    return count;
}

/// Append the check of every record with an invariant on the places a write through `binding` changes, innermost
/// first: the records on the matched place's path above the binding, then, when that place is rooted at the binding of
/// an enclosing `match mut`, the records on its place, and so on out. Each container is read once into a hidden local
/// of the name `typed.invariant_hold_read`, the one read of a held place the source ownership check allows.
fn bindingChecks(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), bindings: []const Binding, binding: typed.LocalId, checks: *std.ArrayList(typed.StatementId)) Error!void {
    var slot = binding;
    for (0..store_depth) |_| {
        const place = bindingPlace(bindings, slot) orelse return;
        if (placePath(Checker, self, place)) |path| if (carriesOnPath(Checker, self, path)) try heldPathChecks(Checker, self, b, path, checks);
        slot = placeRoot(Checker, self, place) orelse return;
    }
}

/// `checkPath` for a place a running `match mut` arm holds: the root, or the list an element root reads, is read into
/// a hold-read local.
fn heldPathChecks(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), path: PlacePath, checks: *std.ArrayList(typed.StatementId)) Error!void {
    var deepest: ?usize = null;
    for (path.levels[0..path.count], 0..) |level, at| if (self.contract.invariants.contains(level.ty)) {
        deepest = at;
    };
    if (deepest) |last| {
        const root = switch (path.root) {
            .local => |slot| try holdRead(Checker, self, b, try b.read(slot), checks),
            .element => |element| root: {
                const list = self.nodes.items[@backingInt(element.list)];
                const source_value = switch (list.data) {
                    .local => |slot| try b.read(slot),
                    .field => |field| try b.node(list.ty, .{ .field = .{ .base = try b.read(self.nodes.items[@backingInt(field.base)].data.local), .index = field.index } }),
                    else => unreachable,
                };
                const again = try holdRead(Checker, self, b, source_value, checks);
                const holder = try hiddenLocal(Checker, self, "self", element.ty, b.span);
                const read = try b.operation(again, .read, &.{try reuseKey(Checker, self, b, element.index)});
                try checks.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = holder, .value = read } }));
                break :root holder;
            },
        };
        try checkLevels(Checker, self, b, root, path.levels[0 .. last + 1], checks);
    }
    const owner = listOwner(Checker, self, path.root) orelse return;
    const invariant = self.contract.invariants.get(self.locals.items[@backingInt(owner)].ty) orelse return;
    const held = try holdRead(Checker, self, b, try b.read(owner), checks);
    for (invariant.clauses) |attribute| try checks.append(self.allocator, try invariantStatement(Checker, self, attribute, invariant, .{ .held = held, .write = true }));
}

/// A hidden local initialized from `value`, a read of a place a running `match mut` arm holds (FX7b).
fn holdRead(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), value: typed.NodeId, checks: *std.ArrayList(typed.StatementId)) Error!typed.LocalId {
    const held = try hiddenLocal(Checker, self, typed.invariant_hold_read, self.nodes.items[@backingInt(value)].ty, b.span);
    try checks.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = held, .value = value } }));
    return held;
}

/// Check, after each write through a `match mut` payload binding, every record with an invariant on the place the
/// binding writes into, as a direct write's store is checked (FX7b, the user's decision of 13 November): an assignment
/// to the binding or below it (`v = x`, `v += x`, `p.a = x`) and an expression that writes it in place (`take`,
/// `exchange`, `append(mut xs, v)`, `bump(mut v)`). A write inside a nested `match mut` writes through the enclosing
/// binding too. The statement or node is rewritten in place, the checks after the write.
fn checkAfterBindingWrites(comptime Checker: type, self: *Checker, first: usize, first_statement: usize) Error!void {
    const bindings = try collectBindings(Checker, self, first_statement);
    if (bindings.len == 0) return;
    const statement_end = self.statements.items.len;
    for (first_statement..statement_end) |index| {
        const statement = self.statements.items[index];
        const store = switch (statement.data) {
            .assign => |store| store,
            else => continue,
        };
        if (bindingPlace(bindings, store.slot) == null) continue;
        const b: collections.Builder(Checker) = .{ .checker = self, .span = statement.span };
        const marks = Marks.of(self);
        var checks: std.ArrayList(typed.StatementId) = .empty;
        try bindingChecks(Checker, self, b, bindings, store.slot, &checks);
        if (checks.items.len == 0) continue;
        marks.relocate(self, statement.span);
        const write: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = statement.span, .terminates = false, .data = statement.data });
        try checks.insert(self.allocator, 0, write);
        self.statements.items[index] = .{ .span = statement.span, .terminates = statement.terminates, .data = .{ .block = try checks.toOwnedSlice(self.allocator) } };
    }
    const end = self.nodes.items.len;
    for (first..end) |index| {
        var roots: [max_written]typed.LocalId = undefined;
        const count = writtenBindings(Checker, self, bindings, @fromBackingInt(index), &roots);
        if (count == 0) continue;
        const node = self.nodes.items[index];
        const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        const marks = Marks.of(self);
        var checks: std.ArrayList(typed.StatementId) = .empty;
        for (roots[0..count]) |root| try bindingChecks(Checker, self, b, bindings, root, &checks);
        if (checks.items.len == 0) continue;
        const write = try b.node(node.ty, node.data);
        const held: ?typed.LocalId = if (node.ty == .unit) null else try hiddenLocal(Checker, self, "self", node.ty, node.span);
        try checks.insert(self.allocator, 0, try b.stmt(if (held) |slot| .{ .initialize = .{ .slot = slot, .value = write } } else .{ .discard = write }));
        marks.relocate(self, node.span);
        const body = try b.stmt(.{ .block = try checks.toOwnedSlice(self.allocator) });
        const value = if (held) |slot| try b.read(slot) else try b.node(.unit, .unit);
        self.nodes.items[index] = .{ .ty = node.ty, .span = node.span, .data = .{ .block_value = .{ .body = body, .value = value } } };
    }
}

/// Where the checker's tables ended before checks were added, so they can be located at the write.
const Marks = struct {
    nodes: usize,
    statements: usize,
    locals: usize,

    fn of(self: anytype) Marks {
        return .{ .nodes = self.nodes.items.len, .statements = self.statements.items.len, .locals = self.locals.items.len };
    }

    fn relocate(marks: Marks, self: anytype, span: Span) void {
        relocateChecks(self.nodes.items[marks.nodes..], self.statements.items[marks.statements..], self.locals.items[marks.locals..], span);
    }
};

/// Whether a fixed-array key can be read again after the store: a literal or
/// a local the store does not change.
fn reusableKey(node: typed.Node) bool {
    return node.data == .integer or node.data == .local;
}

/// A fresh node reading the same fixed-array key again.
fn reuseKey(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), key: typed.NodeId) Error!typed.NodeId {
    const node = self.nodes.items[@backingInt(key)];
    return b.node(node.ty, node.data);
}

/// Inlined invariant code belongs to its use site, including operators and
/// temporary binding metadata that the checked-body cache relocates separately.
fn relocateChecks(nodes: []typed.Node, statements: []typed.Statement, locals: []typed.Local, span: Span) void {
    for (nodes) |*node| {
        node.span = span;
        switch (node.data) {
            .unary => |*unary| unary.op_span = span,
            .binary => |*binary| binary.op_span = span,
            else => {},
        }
    }
    for (statements) |*statement| statement.span = span;
    for (locals) |*local| {
        local.declaration = span;
        if (local.ownership.transfer_span != null) local.ownership.transfer_span = span;
        if (local.usage.dead_write_span != null) local.usage.dead_write_span = span;
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
        // A clause may read `result` or `self`; the `<return>` holder is never read by one.
        .ownership = .{ .initialized = true, .transfer_available = name[0] != '<' and self.transfers(ty) },
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

/// The names after `self.` in an invariant's condition, each once, in the order they are written.
fn fieldsRelated(allocator: std.mem.Allocator, condition: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, condition, at, "self.")) |found| {
        at = found + "self.".len;
        if (found > 0 and (std.ascii.isAlphanumeric(condition[found - 1]) or condition[found - 1] == '_' or condition[found - 1] == '.')) continue;
        var end = at;
        while (end < condition.len and (std.ascii.isAlphanumeric(condition[end]) or condition[end] == '_')) end += 1;
        if (end == at) continue;
        var seen = false;
        for (names.items) |known| seen = seen or std.mem.eql(u8, known, condition[at..end]);
        if (!seen) try names.append(allocator, condition[at..end]);
    }
    return names.items;
}

/// What a trap of an invariant over two fields or more adds when a write broke it (SP2-F-8): each write is checked on its own,
/// so the first of two writes that restore the invariant traps, and `replace(...)` writes the fields together. Null for an
/// invariant over one field, where there is no second write to wait for. The text holds no backtick: the trap's reader takes
/// the last one as the end of the clause.
fn writeHint(allocator: std.mem.Allocator, condition: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const fields = try fieldsRelated(allocator, condition);
    if (fields.len < 2) return null;
    var list: std.ArrayList(u8) = .empty;
    for (fields[0..@min(fields.len, 4)], 0..) |name, i| {
        if (i != 0) try list.appendSlice(allocator, ", ");
        try list.appendSlice(allocator, name);
    }
    if (fields.len > 4) try list.appendSlice(allocator, ", ...");
    const hint = try std.fmt.allocPrint(
        allocator,
        "each write is checked on its own: to change the fields this invariant relates ({s}) together, write them in one replace(record, field=value, ...)",
        .{list.items},
    );
    return hint;
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
    const ownership = try self.pendingState(self.locals.items.len);
    const condition = try self.expressionExpected(condition_id, .bool);
    try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(condition_id)].span);
    // A condition only observes: it may not take a move-only or result-bearing
    // value away from the body or the caller that still owns it.
    for (self.locals.items[0..ownership.len], ownership) |local, before| if (before.available and !local.ownership.transfer_available) {
        const message = try std.fmt.allocPrint(self.allocator, "a contract condition only observes, so it cannot take ownership of `{s}`", .{local.name});
        return self.sink.fail(effect_code, self.syntax.nodes.items[@backingInt(condition_id)].span, message);
    };
    for (self.resolved_nodes.items[saved_resolved..]) |index| self.resolved.put(index, null);
    self.resolved_nodes.shrinkRetainingCapacity(saved_resolved);
    const literal = if (clause.attribute.argument) |argument| try byte_literal.decode(self.allocator, self.src, argument, self.sink) else null;
    const clause_text = self.src.text(self.syntax.nodes.items[@backingInt(condition_id)].span);
    const stated = if (clause.context) |context|
        (if (literal) |text| try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ context, text }) else context)
    else
        literal;
    const hint = if (clause.write) try writeHint(self.allocator, clause_text) else null;
    const note = if (hint) |text| (if (stated) |earlier| try std.fmt.allocPrint(self.allocator, "{s}; {s}", .{ earlier, text }) else text) else stated;
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
        for (self.resolved_nodes.items[saved_resolved..]) |index| self.resolved.put(index, null);
        self.resolved_nodes.shrinkRetainingCapacity(saved_resolved);
    }
    for (self.contract.olds) |old| {
        const call = self.syntax.nodes.items[@backingInt(old.node)];
        const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = call.span, .ty = self.locals.items[@backingInt(old.slot)].ty, .data = .{ .local = old.slot } });
        self.resolved.put(@backingInt(old.node), read);
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
fn invariantStatement(comptime Checker: type, self: *Checker, attribute: ast.Attribute, invariant: Invariant, site: Site) Error!typed.StatementId {
    const held = site.held;
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
    // The clause reads `held` right after the write or construction that
    // reached it, where it is bound. The check is made after the whole body,
    // whose definite-assignment state may call it unbound: a `match mut`
    // binding whose other arm falls through, or a local of an inner block.
    const slot = @backingInt(held);
    const initialized = self.locals.items[slot].ownership.initialized;
    self.locals.items[slot].ownership.initialized = true;
    defer self.locals.items[slot].ownership.initialized = initialized;
    return clauseStatement(Checker, self, .{ .attribute = attribute, .kind = .invariant, .subject = invariant.name, .write = site.write });
}

/// PROPERTY-TEST-2: the invariants a test's parameters must hold, checked on
/// entry before its own preconditions. A value `selka test` copies into a
/// test was never built by a constructor, so no construction checked it; each
/// clause of every invariant-carrying record, domain, element, entry, case or
/// field the parameter holds is checked here as a precondition of the test
/// (`R_REQUIRES`, with the test as the innermost frame), which is how the
/// runner tells a generated input to discard from a failure. A value built
/// by guest code already holds its invariants, so a direct call passes them.
fn harnessPrologue(comptime Checker: type, self: *Checker, function: ast.Function, subject: []const u8, attributes: []const ast.Attribute) Error![]const typed.StatementId {
    if (self.contract.invariants.count() == 0 or function.signature.parameters.len == 0) return &.{};
    var marked = false;
    for (attributes) |attribute| marked = marked or attribute.kind == .@"test";
    if (!marked and !std.mem.startsWith(u8, self.src.text(function.name), "test_")) return &.{};
    var statements: std.ArrayList(typed.StatementId) = .empty;
    for (function.signature.parameters, 0..) |parameter, index| {
        const walk: Walk = .{ .subject = subject, .parameter = self.src.text(parameter.name), .span = parameter.name };
        try harnessValue(Checker, self, walk, @fromBackingInt(index), 0, &statements);
    }
    return statements.toOwnedSlice(self.allocator);
}

/// Where a harness check runs and what its trap names: the test, the
/// parameter whose value is checked, and that parameter's span, which every
/// check's nodes carry so a trap points into the test's own declaration.
const Walk = struct { subject: []const u8, parameter: []const u8, span: Span };
/// How deep into nested values the harness checks reach; generated inputs
/// nest far less than this.
const harness_depth = 16;

/// Check every invariant the value held in `slot` carries, then descend into
/// the values it holds.
fn harnessValue(comptime Checker: type, self: *Checker, walk: Walk, slot: typed.LocalId, depth: usize, out: *std.ArrayList(typed.StatementId)) Error!void {
    const ty = self.locals.items[@backingInt(slot)].ty;
    if (depth > harness_depth or !try carries(Checker, self, ty)) return;
    if (self.contract.invariants.get(ty)) |invariant| for (invariant.clauses) |attribute| {
        try out.append(self.allocator, try harnessClause(Checker, self, walk, attribute, invariant, slot));
    };
    const record = self.catalog.records[ty.recordIndex()];
    const b: collections.Builder(Checker) = .{ .checker = self, .span = walk.span };
    if (record.isCollection()) return harnessCollection(Checker, self, walk, slot, depth, out);
    if (record.shape.variants) |variants| return out.append(self.allocator, try harnessCases(Checker, self, walk, slot, variants.cases, depth));
    if (record.shape.array) |array| {
        const cursor = try b.local(.i64);
        const element = try hiddenLocal(Checker, self, "self", array.element, walk.span);
        const read = try b.node(array.element, .{ .index = .{ .base = try b.read(slot), .index = try b.read(cursor) } });
        return harnessLoop(Checker, self, walk, .{ .cursor = cursor, .count = try b.integer(@intCast(array.length)), .binds = &.{.{ .slot = element, .value = read }} }, depth, out);
    }
    if (record.shape.domain != null) return;
    for (record.fields, 0..) |field, index| {
        if (field.boxed or !try carries(Checker, self, field.ty)) continue;
        const held = try hiddenLocal(Checker, self, "self", field.ty, walk.span);
        const value = try b.node(field.ty, .{ .field = .{ .base = try b.read(slot), .index = index } });
        try out.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = held, .value = value } }));
        try harnessValue(Checker, self, walk, held, depth + 1, out);
    }
}
/// One iteration of a harness loop: the index local, the bound it runs
/// below, and the locals each iteration binds before checking them.
const Iteration = struct { cursor: typed.LocalId, count: typed.NodeId, binds: []const typed.Store };
/// A list's elements, or a dictionary's keys and values, or a set's elements,
/// each checked in turn by position without copying the collection.
fn harnessCollection(comptime Checker: type, self: *Checker, walk: Walk, slot: typed.LocalId, depth: usize, out: *std.ArrayList(typed.StatementId)) Error!void {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = walk.span };
    const record = self.catalog.records[self.locals.items[@backingInt(slot)].ty.recordIndex()];
    const cursor = try b.local(.i64);
    const position = try b.read(cursor);
    var binds: std.ArrayList(typed.Store) = .empty;
    const element = record.shape.buffer.?;
    if (record.collection.key) |key| {
        if (try carries(Checker, self, key)) try binds.append(self.allocator, .{ .slot = try hiddenLocal(Checker, self, "self", key, walk.span), .value = try b.operation(slot, .key_at, &.{position}) });
        if (try carries(Checker, self, element)) try binds.append(self.allocator, .{ .slot = try hiddenLocal(Checker, self, "self", element, walk.span), .value = try b.operation(slot, .value_at, &.{position}) });
    } else try binds.append(self.allocator, .{ .slot = try hiddenLocal(Checker, self, "self", element, walk.span), .value = try b.operation(slot, .read, &.{position}) });
    try harnessLoop(Checker, self, walk, .{ .cursor = cursor, .count = try b.length(slot), .binds = binds.items }, depth, out);
}
/// `for cursor in range(count)`: bind each iteration's locals and check them.
fn harnessLoop(comptime Checker: type, self: *Checker, walk: Walk, iteration: Iteration, depth: usize, out: *std.ArrayList(typed.StatementId)) Error!void {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = walk.span };
    const limit = try b.local(.i64);
    try out.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = limit, .value = iteration.count } }));
    try out.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = iteration.cursor, .value = try b.integer(0) } }));
    var body: std.ArrayList(typed.StatementId) = .empty;
    for (iteration.binds) |bind| {
        try body.append(self.allocator, try b.stmt(.{ .initialize = bind }));
        try harnessValue(Checker, self, walk, bind.slot, depth + 1, &body);
    }
    const i = try b.read(iteration.cursor);
    const loop_id = self.loops.next;
    self.loops.next += 1;
    try out.append(self.allocator, try b.stmt(.{ .loop = .{
        .id = loop_id,
        .condition = try b.binary(.lt, i, try b.read(limit), .bool),
        .body = try b.stmt(.{ .block = try body.toOwnedSlice(self.allocator) }),
        .step = try b.stmt(.{ .assign = .{ .slot = iteration.cursor, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    } }));
}
/// A union, `Option` or `Result`: one arm per case, checking the payload of
/// the cases whose payload carries an invariant.
fn harnessCases(comptime Checker: type, self: *Checker, walk: Walk, slot: typed.LocalId, cases: []const typed.Variant, depth: usize) Error!typed.StatementId {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = walk.span };
    const arms = try self.allocator.alloc(typed.MatchArm, cases.len);
    for (cases, arms, 0..) |case, *arm, tag| {
        var body: std.ArrayList(typed.StatementId) = .empty;
        var payload: ?typed.LocalId = null;
        // A boxed payload closes a recursive value type (RECURSIVE-VALUES-2):
        // the harness checks invariants down to it, not through every level
        // of an input of unbounded depth.
        if (case.payload) |payload_type| if (!case.boxed and try carries(Checker, self, payload_type)) {
            payload = try hiddenLocal(Checker, self, "self", payload_type, walk.span);
            try harnessValue(Checker, self, walk, payload.?, depth + 1, &body);
        };
        arm.* = .{ .tag = tag, .slot = payload, .body = try b.stmt(.{ .block = try body.toOwnedSlice(self.allocator) }) };
    }
    return b.stmt(.{ .match = .{ .value = try b.read(slot), .arms = arms, .borrowed = true } });
}
/// One invariant clause checked on a harness-supplied value, as a
/// precondition of the test that names the parameter holding it.
fn harnessClause(comptime Checker: type, self: *Checker, walk: Walk, attribute: ast.Attribute, invariant: Invariant, held: typed.LocalId) Error!typed.StatementId {
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
    const checked_nodes = self.nodes.items.len;
    const checked_statements = self.statements.items.len;
    const checked_locals = self.locals.items.len;
    const context = try std.fmt.allocPrint(self.allocator, "parameter {s} holds a {s} that breaks this invariant", .{ walk.parameter, invariant.name });
    const statement = try clauseStatement(Checker, self, .{ .attribute = attribute, .kind = .requires, .subject = walk.subject, .context = context });
    // The clause is declared on the type, possibly in another module; its
    // check runs in the test, so it reports the parameter's own location.
    relocateChecks(self.nodes.items[checked_nodes..], self.statements.items[checked_statements..], self.locals.items[checked_locals..], walk.span);
    return statement;
}
/// Whether a value of this type holds, at any depth a generator reaches, a
/// record or domain that carries `@invariant`. A `class` is never generated
/// and never descended into.
fn carries(comptime Checker: type, self: *Checker, ty: typed.Type) Error!bool {
    var seen: std.AutoHashMapUnmanaged(typed.Type, void) = .empty;
    defer seen.deinit(self.allocator);
    return reach(Checker, self, ty, &seen);
}
fn reach(comptime Checker: type, self: *Checker, ty: typed.Type, seen: *std.AutoHashMapUnmanaged(typed.Type, void)) Error!bool {
    if (!ty.isAggregate()) return false;
    if (self.contract.invariants.contains(ty)) return true;
    if ((try seen.getOrPut(self.allocator, ty)).found_existing) return false;
    const record = self.catalog.records[ty.recordIndex()];
    if (record.isManagedRecord()) return false;
    if (record.isCollection()) {
        if (record.collection.key) |key| if (try reach(Checker, self, key, seen)) return true;
        return reach(Checker, self, record.shape.buffer.?, seen);
    }
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (try reach(Checker, self, payload, seen)) return true;
        return false;
    }
    if (record.shape.array) |array| return reach(Checker, self, array.element, seen);
    for (record.fields) |field| if (try reach(Checker, self, field.ty, seen)) return true;
    return false;
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
    var value = try self.expression(argument);
    const node = self.nodes.items[@backingInt(value)];
    if (shared(self.catalog.records, node)) {
        const text = self.src.text(self.syntax.nodes.items[@backingInt(argument)].span);
        const type_name = try typed.surfaceTypeName(self.allocator, node.ty, self.catalog.records);
        const message = try std.fmt.allocPrint(
            self.allocator,
            "`old({s})` would see the value after the body changed it, because `{s}` shares storage with the caller; " ++
                "capture a scalar such as `old(len({s}))`, or a fresh copy such as `old(copy({s}))`",
            .{ text, type_name, text, text },
        );
        return self.sink.failOwnership(.{ .code = old_shared_code, .rule = .C2 }, call.span, message);
    }
    // Hidden receivers normally borrow a place; old must hold an independent
    // entry value. That copy is written: a managed place (a parameter, a field,
    // an element) is refused with the repair `old(copy(x))` (W4). Any other
    // value keeps the capture's checked deep copy: a fresh one (`copy(x)`, a
    // literal, a slice), which the Core passes fold into it, and a call, whose
    // owned result needs no copy (`W_NEEDLESS_COPY` would remove a written one)
    // and whose borrowed result keeps an implicit one (`cost --sites`: "old capture").
    if (node.ty.isAggregate() and value_semantics.copiesAll(self.catalog.records, node.ty)) {
        if (!fresh(node) and placeRead(self.nodes.items, value)) return unwrittenOld(Checker, self, call.span, self.syntax.nodes.items[@backingInt(argument)].span, node.ty);
        const builder: collections.Builder(Checker) = .{ .checker = self, .span = call.span };
        const copied = try builder.access(value, .copy, &.{}, false);
        value = try builder.node(copied.ty, copied.data);
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

/// Whether the checked value `id` reads a named place: a local or parameter, a field, or an element, through the
/// lowering's wrapper blocks. The capture of such a value copies existing storage (W4).
fn placeRead(nodes: []const typed.Node, id: typed.NodeId) bool {
    var at = id;
    for (0..16) |_| {
        const node = nodes[@backingInt(at)];
        switch (node.data) {
            .local, .field, .index => return true,
            .block_value => |block| at = block.value,
            .buffer_operation => |operation| return operation.kind == .read,
            else => return false,
        }
    }
    return false;
}

/// Refuse `old(x)` of a managed value whose copy no `copy(...)` wrote (W4): the capture copies `x` at every
/// call, so the source spells it, `old(copy(x))`. The repair wraps the argument and is certain.
fn unwrittenOld(comptime Checker: type, self: *Checker, call: Span, argument: Span, ty: typed.Type) Error {
    const text = self.src.text(argument);
    const type_name = try typed.surfaceTypeName(self.allocator, ty, self.catalog.records);
    const message = try std.fmt.allocPrint(
        self.allocator,
        "`old({s})` copies the `{s}` at every call, and a copy is written: write `old(copy({s}))`, " ++
            "or capture a scalar such as `old(len({s}))`",
        .{ text, type_name, text, text },
    );
    const repair = try std.fmt.allocPrint(self.allocator, "copy({s})", .{text});
    return self.sink.failOwnershipFix(.{ .code = old_copy_code, .rule = .C2 }, call, message, .{ .span = argument, .text = repair });
}

/// Whether capturing this checked value in `old(...)` would alias storage the
/// body can still change: its type shares mutable storage, and it is not a
/// fresh copy whose own elements share none. Under value semantics the capture
/// is a value of its own unless it reaches a `class` or Cell
/// (`VALUE-SEMANTICS-7`).
fn shared(records: []const typed.Record, node: typed.Node) bool {
    if (!typed.carriesWritableStorage(records, node.ty)) return false;
    if (value_semantics.copiesAll(records, node.ty)) return false;
    if (!fresh(node)) return true;
    const record = records[node.ty.recordIndex()];
    if (!record.isCollection()) return true;
    if (record.collection.key) |key| if (typed.carriesWritableStorage(records, key)) return true;
    return typed.carriesWritableStorage(records, record.shape.buffer.?);
}

/// Whether a checked expression builds a new collection rather than naming an
/// existing one: a literal, a comprehension, or a copying read such as
/// `copy(xs)`, a slice or `d.keys()`. A call is never assumed fresh: its
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

// O0 build-time probe: retired shared-record identity is the old(...) guard's premise.
test "ownership coverage old shared guard needs shared storage identity" {
    const span = source.Span{ .start = 0, .end = 0 };
    const records = [_]typed.Record{.{ .id = @fromBackingInt(0), .name = "Shared", .declaration = span, .managed = true, .fields = &.{} }};
    const node: typed.Node = .{ .span = span, .ty = @fromBackingInt(typed.Type.record_base), .data = .{ .local = @fromBackingInt(0) } };
    try std.testing.expect(shared(&records, node));
}

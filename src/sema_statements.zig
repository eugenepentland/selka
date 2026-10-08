//! Checking of statements other than loops: `with open(...)`, `with arena()` and
//! scoped blocks, `match` with its payload bindings and wildcard arms, discards,
//! `if`/`elif`/`else`, `return`, `assert`, bindings and assignments, and the
//! binding of a function's parameters. `statement` dispatches every statement
//! kind, including the loops in `sema_loops.zig`. Each check is a free function
//! over the concrete checker type; `Checks` exposes the ones the rest of the
//! checker calls as `self.name(...)`.
const sema_shared = @import("sema_shared.zig");
const collections = @import("collection_lower.zig");
const eResultPath = diagnostic.result_path;
const eShadowing = diagnostic.shadowing;
const eImmutable = diagnostic.immutable;
const eResultDiscard = diagnostic.result_discard;
const variantDeclaredHere = sema_shared.variantDeclaredHere;
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const eWithResource = sema_shared.eWithResource;
const Pending = sema_shared.Pending;
const StatementFlow = sema_shared.StatementFlow;
const prelude = @import("prelude.zig");
const variant_calls = @import("variant_calls.zig");
const eWildcardArm = "E_WILDCARD_ARM";
const ePatternPayload = "E_PATTERN_PAYLOAD";
/// Managed collection methods whose only argument has the receiver's own sequence type.
/// Recognize `case _`, the contextual arm that stands for every remaining variant.
fn wildcard(src: source.Source, arm: anytype) bool {
    if (arm.ty.start != arm.ty.end or arm.bindings.len != 0) return false;
    return std.mem.eql(u8, src.text(arm.name), "_");
}
const CheckedStatement = struct { id: typed.StatementId, terminates: bool, looping: bool = false };
const impl = @This();
/// Bind statement checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Check one statement and report whether control flow can continue after it.
        pub fn statement(self: *Checker, statement_id: ast.StatementId) Error!CheckedStatement {
            return impl.statement(Checker, self, statement_id);
        }
        /// Append the implicit `return` a unit function's body falls through to, after
        /// requiring every result-bearing local to be handled.
        pub fn unitFallthrough(self: *Checker, body: CheckedStatement, span: source.Span) Error!CheckedStatement {
            return impl.unitFallthrough(Checker, self, body, span);
        }
    };
}
/// A file `with` scope binds one open handle and closes it at every exit.
fn statementWithFile(comptime Checker: type, self: *Checker, stmt: ast.Statement, scope: @FieldType(@FieldType(ast.Statement, "data"), "with_scope"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const head = self.syntax.nodes.items[@backingInt(scope.resource.?)];
    if (head.data == .call) {
        const kind = try self.fileAccessBuiltin(head.data.call) orelse self.fileAccessMethodKind(head.data.call);
        if (kind) |access| {
            if (access == .open) self.trapping_open = head.span;
        }
    }
    // `with ctx.fs.open(...)`: the receiver is an expression, so the parser hands
    // the head over as a method call whose name alone identifies `open`.
    if (head.data == .method_call and std.mem.eql(u8, self.src.text(head.data.method_call.name), "open")) self.trapping_open = head.span;
    defer self.trapping_open = null;
    const value = try self.expression(scope.resource.?);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    if (!value_type.isFile()) {
        const guidance = if (typed.resultShape(value_type, self.catalog.records) != null)
            "`with` opens an arena or a file; `open` returns a Result, so propagate it with `open(...)?` or match it first"
        else
            "`with` opens `arena()` or a file handle; no other value can be used as a resource";
        return self.sink.fail(eWithResource, self.nodes.items[@backingInt(value)].span, guidance);
    }
    const declared = scope.name orelse return self.sink.fail(eWithResource, stmt.span, "a file `with` scope requires a binding, as in `with open(fs, path, \"rb\")? as f:`");
    const name = self.src.text(declared);
    if (try self.shadows(declared)) return self.sink.fail(eShadowing, declared, "file name shadows an active name");
    if (!std.mem.eql(u8, name, "_")) for (self.arenas.items) |active| if (std.mem.eql(u8, active.name, name)) return self.sink.fail(eShadowing, declared, "file name shadows an enclosing arena scope");
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{ .name = name, .declaration = declared, .ty = value_type, .mutable = false, .ownership = .{ .initialized = true }, .usage = .{ .reads = 1 } });
    const hidden = try self.bindScoped(name, slot);
    defer self.unbindScoped(name, hidden);
    const body = try statement(Checker, self, scope.body);
    flow.terminates = body.terminates;
    return .{ .with_scope = .{ .slot = slot, .resource = value, .body = body.id } };
}
fn statementWithScope(comptime Checker: type, self: *Checker, stmt: ast.Statement, scope: @FieldType(@FieldType(ast.Statement, "data"), "with_scope"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    if (scope.resource != null) return statementWithFile(Checker, self, stmt, scope, flow);
    // NEW-CORE-S5-ARENA-1: the new core runs an arena block as an ordinary block
    // (S5-D3); `arena_fix.warn` reports it after the bodies are checked.
    var name: []const u8 = "";
    if (scope.name) |declared| {
        name = self.src.text(declared);
        if (try self.shadows(declared)) return self.sink.fail(eShadowing, declared, "arena name shadows an active name");
        if (!std.mem.eql(u8, name, "_")) for (self.arenas.items) |active| if (std.mem.eql(u8, active.name, name)) return self.sink.fail(eShadowing, declared, "arena name shadows an enclosing arena scope");
    }
    const watermark: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.arenas.append(self.allocator, .{ .name = name });
    defer _ = self.arenas.pop();
    const body = try statement(Checker, self, scope.body);
    flow.terminates = body.terminates;
    return .{ .with_scope = .{ .slot = watermark, .resource = null, .body = body.id } };
}
fn statementBlock(comptime Checker: type, self: *Checker, stmt: ast.Statement, children: @FieldType(@FieldType(ast.Statement, "data"), "block"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const first_local = self.locals.items.len;
    // Plain (copyable and garbage-collected) locals are function-scoped and stay
    // visible after the block. A move-only resource carries a cleanup obligation
    // discharged at block exit, so it remains confined to the block.
    defer for (self.locals.items[first_local..]) |local| {
        if (typed.moveOnly(local.ty, self.catalog.records)) _ = self.active.remove(local.name);
    };
    var checked: std.ArrayList(typed.StatementId) = .empty;
    var looping = false;
    for (children) |child| {
        if (flow.terminates and !looping) return self.sink.fail("E_UNREACHABLE", self.syntax.statements.items[@backingInt(child)].span, "statement follows a structurally terminating statement");
        const result = try statement(Checker, self, child);
        flow.terminates = result.terminates;
        looping = result.looping;
        try checked.append(self.allocator, result.id);
    }
    flow.looping = looping;
    if (!flow.terminates) try self.requireHandled(first_local, stmt.span);
    return .{ .block = try checked.toOwnedSlice(self.allocator) };
}
fn patternTag(comptime Checker: type, self: *Checker, value_type: typed.Type, type_span: source.Span, name: source.Span) Error!usize {
    if (type_span.start != type_span.end) {
        const contextual = try variant_calls.contextual(self.src, self.catalog, type_span, value_type, self.sink);
        try self.require(contextual orelse try self.ty(type_span), value_type, type_span);
        return self.catalog.variant(value_type, self.src, name, self.sink);
    }
    const spelling = self.src.text(name);
    const canonical = prelude.caseName(spelling);
    const variants = try self.catalog.variants(value_type, name, self.sink);
    for (variants.cases, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate.name, canonical)) return index;
    }
    return self.sink.fail("E_UNKNOWN_VARIANT", name, "case is not a variant of the matched type");
}
/// Give every variant no earlier arm named the wildcard's body, discarding its payload.
fn wildcardArms(
    comptime Checker: type,
    self: *Checker,
    arms: *std.ArrayList(typed.MatchArm),
    shape: struct { seen: []?source.Span, variants: typed.Variants, name: source.Span },
    body: typed.StatementId,
) Error!void {
    var covered: usize = 0;
    for (shape.seen, shape.variants.cases, 0..) |named, variant, tag| {
        if (named != null) continue;
        if (variant.payload) |payload| if (self.requiresHandling(payload)) return self.sink.fail(
            eResultDiscard,
            shape.name,
            "`case _` would drop a result-bearing payload; give that variant its own arm",
        );
        shape.seen[tag] = shape.name;
        covered += 1;
        try arms.append(self.allocator, .{ .tag = tag, .slot = null, .body = body });
    }
    if (covered == 0) return self.sink.fail(eWildcardArm, shape.name, "every variant already has an arm, so `case _` is unreachable");
}
/// Per-arm payload locals: the slot the lowering binds the payload into, the
/// field-projection prologue that initializes visible bindings, and the names
/// to remove from scope after the arm.
const ArmBindings = struct {
    slot: ?typed.LocalId = null,
    prologue: []const typed.StatementId = &.{},
    names: []const []const u8 = &.{},
    fielded: bool = false,
};
fn bindArmPayload(comptime Checker: type, self: *Checker, case_schema: typed.Variant, arm: ast.MatchArm) Error!ArmBindings {
    if (case_schema.fielded) return bindFieldedPayload(Checker, self, case_schema, arm);
    const payload = case_schema.payload;
    if (arm.bindings.len > 1) return self.sink.failRelated(
        ePatternPayload,
        arm.name,
        "a single-payload case binds one name",
        .{ .span = case_schema.declaration, .message = variantDeclaredHere },
    );
    const discards_payload = arm.bindings.len == 1 and arm.bindings[0] == null;
    if (discards_payload and payload != null and self.requiresHandling(payload.?)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires a binding and explicit handling");
    if ((payload != null) != (arm.bindings.len == 1)) return self.sink.failRelated(
        ePatternPayload,
        arm.name,
        "payload variants require a binding or (discard); empty variants take neither",
        .{ .span = case_schema.declaration, .message = variantDeclaredHere },
    );
    if (arm.bindings.len == 0) return .{};
    const binding = arm.bindings[0] orelse return .{};
    const name = self.src.text(binding);
    if (try self.topLevel(binding) or self.active.contains(name)) return self.sink.fail(eShadowing, binding, "payload binding shadows an active binding or top-level name");
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{ .initialized = true, .transfer_available = self.transfers(payload.?) },
        .name = name,
        .declaration = binding,
        .ty = payload.?,
        .mutable = false,
    });
    try self.active.put(self.allocator, name, slot);
    return .{ .slot = slot, .names = try self.allocator.dupe([]const u8, &.{name}) };
}
/// Bind one name per named field. The lowering still stores the payload
/// record in a hidden slot; every visible binding is a `.field` projection
/// of it, so typed IR, bytecode and native lowering stay single-slot.
fn bindFieldedPayload(comptime Checker: type, self: *Checker, case_schema: typed.Variant, arm: ast.MatchArm) Error!ArmBindings {
    const payload = case_schema.payload orelse return error.InternalError;
    const record = try self.catalog.record(payload, arm.name, self.sink);
    if (arm.bindings.len != record.fields.len) return self.sink.failRelated(
        ePatternPayload,
        arm.name,
        "a named-field case pattern binds exactly one name per field, using `_` to discard one",
        .{ .span = case_schema.declaration, .message = variantDeclaredHere },
    );
    var all_discard = true;
    for (arm.bindings) |binding| if (binding != null) {
        all_discard = false;
        break;
    };
    // A pattern that discards every field behaves exactly like `case _` over
    // the whole payload, including its cleanup.
    if (all_discard) {
        if (self.requiresHandling(payload)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires a binding and explicit handling");
        return .{};
    }
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{ .initialized = true },
        .usage = .{ .reads = 1, .temporary = true },
        .name = "",
        .declaration = arm.name,
        .ty = payload,
        .mutable = false,
    });
    var prologue: std.ArrayList(typed.StatementId) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    for (arm.bindings, record.fields, 0..) |binding, field_info, index| {
        const binding_span = binding orelse {
            if (self.requiresHandling(field_info.ty)) return self.sink.failRelated(
                eResultDiscard,
                arm.name,
                "discarding this field would drop a result-bearing payload; bind it and handle the result",
                .{ .span = field_info.declaration, .message = "result-bearing field declared here" },
            );
            continue;
        };
        const name = self.src.text(binding_span);
        if (try self.topLevel(binding_span) or self.active.contains(name)) return self.sink.fail(eShadowing, binding_span, "payload binding shadows an active binding or top-level name");
        const binding_slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .ownership = .{ .initialized = true, .transfer_available = self.transfers(field_info.ty) },
            .name = name,
            .declaration = binding_span,
            .ty = field_info.ty,
            .mutable = false,
        });
        try self.active.put(self.allocator, name, binding_slot);
        try names.append(self.allocator, name);
        const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = arm.name, .ty = payload, .data = .{ .local = slot } });
        const projected: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = binding_span, .ty = field_info.ty, .data = .{ .field = .{ .base = base, .index = index } } });
        try prologue.append(self.allocator, @fromBackingInt(self.statements.items.len));
        try self.statements.append(self.allocator, .{ .span = binding_span, .terminates = false, .data = .{ .initialize = .{ .slot = binding_slot, .value = projected } } });
    }
    return .{ .slot = slot, .prologue = try prologue.toOwnedSlice(self.allocator), .names = try names.toOwnedSlice(self.allocator), .fielded = true };
}
fn statementMatch(comptime Checker: type, self: *Checker, stmt: ast.Statement, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    for (match.arms) |arm| try self.invalidateOptions(arm.body);
    const match_facts = try self.option_facts.snapshot(self.allocator);
    defer self.option_facts.restore(match_facts);
    try self.hintOptionOperand(match.value);
    const value = try self.expression(match.value);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    const variants = try self.catalog.variants(value_type, stmt.span, self.sink);
    const seen = try self.allocator.alloc(?source.Span, variants.cases.len);
    @memset(seen, null);
    var arms: std.ArrayList(typed.MatchArm) = .empty;
    const before = try self.pendingState(self.locals.items.len);
    const init_before = try self.initSnapshot();
    var continuation: ?[]Pending = null;
    var continuation_init: ?[]bool = null;
    flow.terminates = true;
    for (match.arms, 0..) |arm, position| {
        self.option_facts.restore(match_facts);
        self.restorePending(before);
        // Every arm starts from the same pre-match definite-assignment state.
        self.initRestore(init_before);
        if (wildcard(self.src, arm)) {
            if (position + 1 != match.arms.len) return self.sink.fail(eWildcardArm, arm.name, "`case _` must be the last arm of a match");
            const body = try statement(Checker, self, arm.body);
            if (!body.terminates) {
                try self.mergeMatchInit(&continuation_init);
                if (continuation) |state| try self.samePending(state, stmt.span, eResultPath) else continuation = try self.pendingState(before.len);
            }
            flow.terminates = flow.terminates and body.terminates;
            try wildcardArms(Checker, self, &arms, .{ .seen = seen, .variants = variants, .name = arm.name }, body.id);
            continue;
        }
        const tag = try patternTag(Checker, self, value_type, arm.ty, arm.name);
        if (seen[tag]) |previous| return self.sink.failRelated("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm", .{ .span = previous, .message = "previous arm" });
        seen[tag] = arm.name;
        const case_schema = variants.cases[tag];
        const first_local = self.locals.items.len;
        const arm_bindings = try bindArmPayload(Checker, self, case_schema, arm);
        defer for (arm_bindings.names) |name| {
            _ = self.active.remove(name);
        };
        var body = try statement(Checker, self, arm.body);
        // The field-projection prologue must run on every path into the arm,
        // including one whose body returns immediately.
        if (arm_bindings.prologue.len != 0) {
            const children = try self.allocator.alloc(typed.StatementId, arm_bindings.prologue.len + 1);
            @memcpy(children[0..arm_bindings.prologue.len], arm_bindings.prologue);
            children[arm_bindings.prologue.len] = body.id;
            body.id = @fromBackingInt(self.statements.items.len);
            try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = body.terminates, .data = .{ .block = children } });
        }
        if (!body.terminates) {
            try self.mergeMatchInit(&continuation_init);
            try self.requireHandled(first_local, stmt.span);
            if (continuation) |state| try self.samePending(state, stmt.span, eResultPath) else continuation = try self.pendingState(before.len);
        }
        flow.terminates = flow.terminates and body.terminates;
        try arms.append(self.allocator, .{ .tag = tag, .slot = arm_bindings.slot, .body = body.id });
    }
    for (seen, variants.cases) |covered, variant| if (covered == null) {
        const message = try std.fmt.allocPrint(self.allocator, "match does not handle variant `{s}`; every variant requires an explicit arm", .{variant.name});
        return self.sink.failRelated("E_INCOMPLETE_MATCH", stmt.span, message, .{ .span = variant.declaration, .message = "unhandled variant declared here" });
    };
    if (continuation) |state| self.restorePending(state);
    if (continuation_init) |state| self.initRestore(state) else self.initRestore(init_before);
    return .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.allocator) } };
}
fn statementDiscard(comptime Checker: type, self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "discard"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const value = try self.expression(expr);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    if (stmt.implicit_discard and value_type != .unit) {
        const message = "a standalone non-unit value requires `_ =` or result handling";
        // A result is left to the reader: discarding it would drop an error.
        if (self.requiresHandling(value_type)) return self.sink.fail("E_EXPLICIT_DISCARD_REQUIRED", stmt.span, message);
        return self.sink.failFix("E_EXPLICIT_DISCARD_REQUIRED", stmt.span, message, .{ .span = .{ .start = stmt.span.start, .end = stmt.span.start }, .text = "_ = " });
    }
    return .{ .discard = value };
}
fn statementBranch(comptime Checker: type, self: *Checker, stmt: ast.Statement, branch: @FieldType(@FieldType(ast.Statement, "data"), "branch"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const condition = try self.expression(branch.condition);
    try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(branch.condition)].span);
    const before = try self.pendingState(self.locals.items.len);
    const init_before = try self.initSnapshot();
    const facts_before = try self.option_facts.snapshot(self.allocator);
    try self.assumeOption(branch.condition, true);
    const then_body = try statement(Checker, self, branch.then_body);
    const facts_then = try self.option_facts.snapshot(self.allocator);
    const then_state = try self.pendingState(before.len);
    const init_then = try self.initSnapshot();
    self.restorePending(before);
    self.initRestore(init_before);
    self.option_facts.restore(facts_before);
    try self.assumeOption(branch.condition, false);
    const else_body = if (branch.else_body) |other| try statement(Checker, self, other) else null;
    const then_terminates = then_body.terminates;
    const else_terminates = if (else_body) |other| other.terminates else false;
    if (!then_terminates) {
        if (else_terminates) self.option_facts.restore(facts_then) else self.option_facts.intersect(facts_then);
    }
    // Merge definite assignment: a name is bound after the `if` only when every
    // path that continues bound it. A path that diverges contributes nothing.
    if (then_terminates and !else_terminates) {
        // Continuation is the else path, already reflected in the flags.
    } else if (else_terminates and !then_terminates) {
        self.initRestore(init_then);
    } else if (!then_terminates and !else_terminates) {
        self.initIntersect(init_then);
    }
    if (!then_body.terminates) {
        if (else_body == null or !else_body.?.terminates) try self.samePending(then_state, stmt.span, eResultPath);
        self.restorePending(then_state);
    }
    flow.terminates = then_terminates and else_terminates;
    return .{ .branch = .{ .condition = condition, .then_body = then_body.id, .else_body = if (else_body) |other| other.id else null } };
}
fn unitFallthrough(comptime Checker: type, self: *Checker, body: CheckedStatement, span: source.Span) Error!CheckedStatement {
    try self.requireHandled(0, span);
    const value: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = span, .ty = .unit, .data = .unit });
    // The implicit end of a procedure is a normal return: its postconditions hold there too.
    const data: @FieldType(typed.Statement, "data") = if (self.contract.ensures.len != 0) try self.contractReturn(value, span) else .{ .ret = value };
    const ret: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = data });
    const children = try self.allocator.dupe(typed.StatementId, &.{ body.id, ret });
    const block: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = .{ .block = children } });
    return .{ .id = block, .terminates = true };
}
fn statementRet(comptime Checker: type, self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "ret"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const value = try self.expressionExpected(expr, self.return_type);
    try self.require(self.nodes.items[@backingInt(value)].ty, self.return_type, stmt.span);
    try self.requireHandled(0, stmt.span);
    flow.terminates = true;
    if (self.contract.ensures.len != 0) return self.contractReturn(value, stmt.span);
    return .{ .ret = value };
}
/// `assert` traps instead of returning, so it needs no result type and no effect.
/// A rendered message is checked as `str` here but evaluated only on failure,
/// which is why the effect pass exempts its expression from the ceiling.
fn statementAssert(comptime Checker: type, self: *Checker, claim: ast.Assertion) Error!@FieldType(typed.Statement, "data") {
    const condition = try self.expressionExpected(claim.condition, .bool);
    try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(claim.condition)].span);
    const message_value = if (claim.value) |value| message: {
        const str_type = self.catalog.names.get("str") orelse return error.InternalError;
        const checked = try self.expressionExpected(value, str_type);
        try self.require(self.nodes.items[@backingInt(checked)].ty, str_type, self.syntax.nodes.items[@backingInt(value)].span);
        break :message checked;
    } else null;
    return .{ .assertion = .{ .condition = condition, .message = claim.message, .message_value = message_value } };
}
fn statementBinding(comptime Checker: type, self: *Checker, _: ast.Statement, b: @FieldType(@FieldType(ast.Statement, "data"), "binding"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const name = self.src.text(b.name);
    if (try self.topLevel(b.name) or self.active.contains(name))
        return self.sink.fail(eShadowing, b.name, "binding shadows an active local or top-level function");
    for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, name)) return self.sink.fail(eShadowing, b.name, "binding shadows an active arena name");
    const value = if (b.annotation) |annotation| try self.expressionExpected(b.value, try self.ty(annotation)) else try self.expression(b.value);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    if (b.annotation) |annotation| try self.require(value_type, try self.ty(annotation), annotation);
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{
            .initialized = true,
            .transfer_available = self.transfers(value_type),
        },
        .name = name,
        .declaration = b.name,
        .ty = value_type,
        .mutable = b.mutable,
        // A binding initialized from an index read holds an element copy,
        // which is what makes a later field write dead when never read.
        .origin = if (self.syntax.nodes.items[@backingInt(b.value)].data == .index) .collection_copy else .local,
    });
    try self.active.put(self.allocator, name, slot);
    return .{ .initialize = .{ .slot = slot, .value = value } };
}
fn statementAssignment(comptime Checker: type, self: *Checker, stmt: ast.Statement, a: @FieldType(@FieldType(ast.Statement, "data"), "assignment"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const unbound = !self.active.contains(self.src.text(a.name));
    if (a.op == .set and unbound)
        return statementBinding(Checker, self, stmt, .{ .name = a.name, .mutable = true, .annotation = null, .value = a.value }, flow);
    const slot = try self.resolve(a.name);
    if (!self.locals.items[@backingInt(slot)].mutable)
        return self.sink.fail(eImmutable, a.name, "this binding cannot be assigned");
    try self.requireRebindable(slot, a.name);
    // PY-REPEAT-1: `text *= count` repeats the binding by an integer count.
    if (try self.repeatAssignment(slot, a)) |repeated| return repeated;
    var value = try self.expressionExpected(a.value, self.locals.items[@backingInt(slot)].ty);
    if (a.op != .set) {
        try self.requireReadable(slot, a.name);
        const target_type = self.locals.items[@backingInt(slot)].ty;
        try self.require(self.nodes.items[@backingInt(value)].ty, target_type, a.op_span);
        // `values += other` is Python's in-place extend, not a fresh list.
        if (a.op == .add and target_type.isAggregate() and self.catalog.records[target_type.recordIndex()].isCollection() and self.catalog.records[target_type.recordIndex()].collection.kind == .list) {
            const b: collections.Builder(Checker) = .{ .checker = self, .span = a.op_span };
            const arguments = try self.allocator.alloc(typed.NodeId, 1);
            arguments[0] = value;
            self.locals.items[@backingInt(slot)].usage.reads += 1;
            self.locals.items[@backingInt(slot)].usage.writes += 1;
            return .{ .block = try self.allocator.dupe(typed.StatementId, &.{try b.stmt(.{ .discard = try b.operation(slot, .extend, arguments) })}) };
        }
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .ty = target_type, .span = a.name, .data = .{ .local = slot } });
        value = try self.augmented(a.op, read, value, a.op_span);
    }
    try self.require(self.nodes.items[@backingInt(value)].ty, self.locals.items[@backingInt(slot)].ty, stmt.span);
    if (self.transfers(self.locals.items[@backingInt(slot)].ty)) {
        if (self.pendingObligation(self.locals.items[@backingInt(slot)])) return self.sink.fail("E_RESULT_OVERWRITE", a.name, "assignment would overwrite an unhandled result-bearing value");
        self.locals.items[@backingInt(slot)].ownership.transfer_available = true;
        self.locals.items[@backingInt(slot)].ownership.transfer_span = null;
    }
    self.locals.items[@backingInt(slot)].usage.writes += 1;
    // A plain reassignment re-homes the value, so its copy provenance follows
    // the new initializer; an indexed read still yields an element copy.
    if (a.op == .set) self.locals.items[@backingInt(slot)].origin = if (self.syntax.nodes.items[@backingInt(a.value)].data == .index) .collection_copy else .local;
    // A reassignment definitely binds the name on this path.
    self.locals.items[@backingInt(slot)].ownership.initialized = true;
    self.option_facts.forget(@backingInt(slot));
    return .{ .assign = .{ .slot = slot, .value = value } };
}
/// Check one statement and report whether control flow can continue after it.
fn statement(comptime Checker: type, self: *Checker, statement_id: ast.StatementId) Error!CheckedStatement {
    const stmt = self.syntax.statements.items[@backingInt(statement_id)];
    var flow: StatementFlow = .{};
    const data: @FieldType(typed.Statement, "data") = switch (stmt.data) {
        .with_scope => |scope| try statementWithScope(Checker, self, stmt, scope, &flow),
        .block => |children| try statementBlock(Checker, self, stmt, children, &flow),
        .match => |match| try statementMatch(Checker, self, stmt, match, &flow),
        .discard => |expr| try statementDiscard(Checker, self, stmt, expr, &flow),
        .branch => |branch| try statementBranch(Checker, self, stmt, branch, &flow),
        .loop => |loop| try self.statementLoop(stmt, loop, &flow),
        .ret => |expr| try statementRet(Checker, self, stmt, expr, &flow),
        .loop_exit => |continuing| try self.statementLoopExit(stmt, continuing, &flow),
        .for_each => |each| try self.statementForEach(stmt, each),
        .for_range => |range| try self.statementForRange(stmt, range),
        .assertion => |claim| try statementAssert(Checker, self, claim),
        .binding => |b| try statementBinding(Checker, self, stmt, b, &flow),
        .assignment => |a| try statementAssignment(Checker, self, stmt, a, &flow),
        .gather_step => |step| try self.statementGatherStep(stmt, step),
    };
    try @import("mut_exclusive.zig").checkReceivers(Checker, self, stmt);
    const result: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = flow.terminates, .data = data });
    return .{ .id = result, .terminates = flow.terminates, .looping = flow.looping };
}

test "only a bare case _ with no type and no bindings is the wildcard arm" {
    const src: source.Source = .{ .path = "match.my", .bytes = "_ Some x", .line_starts = &.{} };
    const none: source.Span = .{ .start = 0, .end = 0 };
    const bare = .{ .ty = none, .bindings = &[_]source.Span{}, .name = source.Span{ .start = 0, .end = 1 } };
    const named = .{ .ty = none, .bindings = &[_]source.Span{}, .name = source.Span{ .start = 2, .end = 6 } };
    const bound = .{ .ty = none, .bindings = &[_]source.Span{.{ .start = 7, .end = 8 }}, .name = source.Span{ .start = 0, .end = 1 } };
    try std.testing.expect(wildcard(src, bare));
    try std.testing.expect(!wildcard(src, named));
    try std.testing.expect(!wildcard(src, bound));
}

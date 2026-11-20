//! Checking of statements other than loops: `with open(...)`, `with arena()` and
//! scoped blocks, `match` with its payload bindings and wildcard arms, discards,
//! `if`/`elif`/`else`, `return`, `assert`, bindings and assignments, and the
//! binding of a function's parameters. `statement` dispatches every statement
//! kind, including the loops in `sema_loops.zig`. Each check is a free function
//! over the concrete checker type; `Checks` exposes the ones the rest of the
//! checker calls as `self.name(...)`.
const frontend_failures = @import("frontend_failures.zig");
const recovery = @import("sema_recovery.zig");
const sema_shared = @import("sema_shared.zig");
const collections = @import("collection_lower.zig");
const eResultPath = diagnostic.result_path;
const eShadowing = diagnostic.shadowing;
const eImmutable = diagnostic.immutable;
const eResultDiscard = diagnostic.result_discard;
const variantDeclaredHere = sema_shared.variantDeclaredHere;
const std = @import("std");
const eNamedPattern = "E_NAMED_PATTERN";
const frontend_patterns = @import("frontend_patterns.zig");
const byte_constants = @import("byte_constants.zig");
const pattern_alternatives = @import("pattern_alternatives.zig");
const bind_or_else = @import("bind_or_else.zig");
const unreachable_repair = @import("unreachable_repair.zig");
const case_payload = @import("case_payload.zig");
const own_parameters = @import("own_parameters.zig");
const integers = @import("integers.zig");
const ast = @import("ast.zig");
const number_literal = @import("number_literal.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Pending = sema_shared.Pending;
const StatementFlow = sema_shared.StatementFlow;
const prelude = @import("prelude.zig");
const variant_calls = @import("variant_calls.zig");
const variant_splits = @import("variant_splits.zig");
const eWildcardArm = "E_WILDCARD_ARM";
const eLiteralArm = "E_LITERAL_ARM";
const eIncompleteMatch = "E_INCOMPLETE_MATCH";
const eDuplicateArm = "E_DUPLICATE_ARM";
const ManagedKind = @import("type_identity.zig").ManagedKind;
const ePatternPayload = diagnostic.pattern_payload;
/// Managed collection methods whose only argument has the receiver's own sequence type.
/// Recognize `case _`, the contextual arm that stands for every remaining variant. The generic body check
/// (`generic_bodies.zig`) reads the arm with this too.
pub fn wildcard(src: source.Source, arm: anytype) bool {
    if (@hasField(@TypeOf(arm), "internal")) if (arm.internal.wildcard) return true;
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
        /// Check an exhaustive expression match whose arms yield a common value.
        pub fn matchExpression(self: *Checker, node: ast.Node) Error!typed.Node {
            return impl.matchExpression(Checker, self, node);
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
            if (access.opensFile()) self.trapping_open = head.span;
        }
    }
    // `with ctx.fs.open(...)`: the receiver is an expression, so the parser hands
    // the head over as a method call whose name alone identifies `open`.
    if (head.data == .method_call) {
        const name = self.src.text(head.data.method_call.name);
        const access = std.meta.stringToEnum(@import("file_operations.zig").Access, name);
        if (access != null and access.?.opensFile()) self.trapping_open = head.span;
    }
    defer self.trapping_open = null;
    const value = try self.expression(scope.resource.?);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    const capability_scope = value_type.capabilityIndex() != null and !value_type.isHandle() and value_type != .host_cap;
    if (!value_type.isFile() and !capability_scope) {
        const guidance = if (typed.resultShape(value_type, self.catalog.records) != null)
            "`with` opens an arena or a file; `open` returns a Result, so propagate it with `open(...)?` or match it first"
        else
            "`with` opens `arena()`, a file handle, or a provider capability";
        return self.sink.fail("E_TYPE", self.nodes.items[@backingInt(value)].span, guidance);
    }
    const declared = scope.name orelse return self.sink.fail("E_BINDING_DECLARATION", stmt.span, "a file `with` scope requires a binding, as in `with open(fs, path, \"rb\")? as f:`");
    const name = self.src.text(declared);
    if (try self.shadows(declared)) return self.refuseShadowing(declared, "file name");
    if (!std.mem.eql(u8, name, "_")) for (self.arenas.items) |active| if (std.mem.eql(u8, active.name, name)) return self.sink.fail(eShadowing, declared, "file name shadows an enclosing arena scope");
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{ .name = name, .declaration = declared, .ty = value_type, .mutable = false, .ownership = .{ .initialized = true, .scoped_file = value_type.isFile() }, .usage = .{ .reads = 1 } });
    const hidden = try self.bindScoped(name, slot);
    defer self.unbindScoped(name, hidden);
    const body = try statement(Checker, self, scope.body);
    flow.terminates = body.terminates;
    return .{ .with_scope = .{ .slot = slot, .resource = value, .body = body.id } };
}
fn statementWithScope(comptime Checker: type, self: *Checker, stmt: ast.Statement, scope: @FieldType(@FieldType(ast.Statement, "data"), "with_scope"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    if (scope.resource != null) {
        if (try @import("sema_tasks.zig").opensGroup(Checker, self, scope.resource)) return @import("sema_tasks.zig").statementWithGroup(Checker, self, stmt, scope, flow);
        return statementWithFile(Checker, self, stmt, scope, flow);
    }
    // NEW-CORE-S5-ARENA-1: the new core runs an arena block as an ordinary block
    // (S5-D3); `arena_fix.reject` reports its removal even when a body fails.
    var name: []const u8 = "";
    if (scope.name) |declared| {
        name = self.src.text(declared);
        if (try self.shadows(declared)) return self.refuseShadowing(declared, "arena name");
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
    // Every declaration belongs to its lexical block. Slots remain available
    // to lowering, but their source names leave the active environment here.
    // `_` is the one name a scope may bind over an active binding
    // (`DISCARD-NAME-1`), so a block that holds a nested loop's `_` must hand
    // back the `_` that was active when it began: the scope that bound it
    // restores its own outer `_` when it ends, however deep the nesting goes.
    const outer_discard = self.active.get("_");
    defer {
        // Only a name this block bound leaves: a hidden local the checker made
        // here (a postcondition's `result` holder) never entered the scope, so
        // it must not take an outer local of the same spelling with it.
        for (self.locals.items[first_local..], first_local..) |local, index| {
            const bound = self.active.get(local.name) orelse continue;
            if (@backingInt(bound) == index) _ = self.active.remove(local.name);
        }
        if (outer_discard) |slot| self.active.putAssumeCapacity("_", slot);
    }
    var checked: std.ArrayList(typed.StatementId) = .empty;
    var looping = false;
    var failed = false;
    for (children, 0..) |child, position| {
        if (flow.terminates and !looping) {
            const refused = try unreachable_repair.refusal(self.allocator, self.src, self.syntax.statements.items, children, position, "statement follows a structurally terminating statement");
            return self.sink.failRepaired("E_UNREACHABLE", self.syntax.statements.items[@backingInt(child)].span, refused.message, refused.fix);
        }
        const before = self.sink.items.items.len;
        const result = statement(Checker, self, child) catch |err| {
            if (err != error.SourceError or !try recovery.resumeAfter(Checker, self, child, before)) return err;
            try recovery.siblingImports(Checker, self, child, before);
            failed = true;
            // What follows a failed `return`, `fail`, `break` or `continue` is unreachable; nothing after it is checked.
            if (endsFlow(self.syntax.statements.items[@backingInt(child)])) break;
            flow.terminates = false;
            looping = false;
            continue;
        };
        flow.terminates = result.terminates;
        looping = result.looping;
        try checked.append(self.allocator, result.id);
    }
    if (failed) {
        recovery.dropHandles(Checker, self, first_local);
        return recovery.failBlock(Checker, self);
    }
    try @import("sema_tasks.zig").closeBlock(Checker, self, first_local);
    flow.looping = looping;
    if (!flow.terminates) try self.requireHandled(first_local, stmt.span);
    return .{ .block = try checked.toOwnedSlice(self.allocator) };
}
/// Whether a statement ends its block's flow wherever it runs: what follows it is unreachable.
fn endsFlow(stmt: ast.Statement) bool {
    return switch (stmt.data) {
        .ret, .fail, .loop_exit => true,
        else => false,
    };
}
/// The refusal for a case pattern spelled with its type (`Shape.circle`).
const eQualifiedPattern = "E_PATTERN_QUALIFIED";
fn patternTag(comptime Checker: type, self: *Checker, value_type: typed.Type, type_span: source.Span, name: source.Span, labelled: bool) Error!usize {
    if (type_span.start != type_span.end) {
        // A labelled field's qualified case keeps its qualifier: its bare name would be the field's rename.
        if (labelled) {
            const contextual = try variant_calls.contextual(self.src, self.catalog, type_span, value_type, self.sink);
            try self.require(contextual orelse try self.ty(type_span), value_type, type_span);
        } else try qualifiedCase(Checker, self, value_type, type_span, name);
    }
    const spelling = self.src.text(name);
    const canonical = prelude.caseName(spelling);
    const variants = try self.catalog.variants(value_type, name, self.sink);
    for (variants.cases, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate.name, canonical)) return index;
    }
    return self.sink.fail("E_UNKNOWN_VARIANT", name, try unknownCaseMessage(self.allocator, spelling, variants));
}
/// Refuse a case pattern spelled with its type. The matched value already names its
/// type, so the case is named alone. The repair drops the qualifier when it names the
/// matched type exactly; a qualifier naming another type is refused with no repair.
/// The arm is checked once per nested group that holds it, so a pattern is reported once.
fn qualifiedCase(comptime Checker: type, self: *Checker, value_type: typed.Type, type_span: source.Span, name: source.Span) Error!void {
    const span: source.Span = .{ .start = type_span.start, .end = name.end };
    for (self.sink.items.items) |item| {
        if (item.span.start == span.start and std.mem.eql(u8, item.code, eQualifiedPattern)) return;
    }
    const contextual = try variant_calls.contextual(self.src, self.catalog, type_span, value_type, self.sink);
    const qualifier = contextual orelse try self.ty(type_span);
    if (qualifier == value_type) return self.sink.appendFix(
        .{ .code = eQualifiedPattern, .span = span, .message = "a case pattern names its case alone; the matched value's type already says which type it is" },
        .{ .span = .{ .start = type_span.start, .end = name.start }, .text = "" },
    );
    try self.sink.items.append(self.sink.allocator, .{
        .code = eQualifiedPattern,
        .span = span,
        .message = "a case pattern names its case alone; this qualifier does not name the matched type",
    });
}
/// The refusal for a bare case name the matched type does not declare. It lists the
/// type's cases, so the reader can see which spelling was meant.
fn unknownCaseMessage(allocator: std.mem.Allocator, spelling: []const u8, variants: typed.Variants) Error![]const u8 {
    var message: std.ArrayList(u8) = .empty;
    try message.appendSlice(allocator, try std.fmt.allocPrint(allocator, "`{s}` is not a case of the matched type; its cases are", .{spelling}));
    for (variants.cases, 0..) |candidate, index| {
        try message.appendSlice(allocator, if (index == 0) " " else ", ");
        try message.appendSlice(allocator, candidate.name);
    }
    return message.toOwnedSlice(allocator);
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
        if (variant.payload) |payload| if (self.requiresHandling(payload)) return self.sink.failOwnership(
            .{ .code = eResultDiscard, .rule = .L1 },
            shape.name,
            "`case _` would drop a result-bearing payload; give that variant its own arm",
        );
        shape.seen[tag] = shape.name;
        covered += 1;
        try arms.append(self.allocator, .{ .tag = tag, .slot = null, .body = body });
    }
    if (covered == 0) return self.sink.fail(eWildcardArm, shape.name, "every variant already has an arm, so `case _` is unreachable");
}
/// F-60: refuse a bare `else:` over a Result, whose failure case carries `payload`. The note is at the called function
/// when the operand is a direct call. Any other arm passes.
fn refuseBareElse(comptime Checker: type, self: *Checker, arm: ast.MatchArm, value: typed.NodeId, payload: ?typed.Type, operand: ast.NodeId) Error!void {
    const failure = payload orelse return;
    if (!bind_or_else.bareElse(self.src, arm)) return;
    const node = self.nodes.items[@backingInt(value)];
    const called: ?source.Span = if (node.data == .call) self.syntaxFunction(node.data.call.function).name else null;
    return bind_or_else.refuseBareElse(self.src, self.sink, arm, .{
        .operand = self.src.text(self.syntax.nodes.items[@backingInt(operand)].span),
        .failure = try typed.surfaceTypeName(self.allocator, failure, self.catalog.records),
        .called = called,
        .droppable = !self.requiresHandling(failure),
        .call = self.syntax.nodes.items[@backingInt(operand)].data == .call,
    });
}
/// Per-arm payload locals: the slot the lowering binds the payload into, the
/// field-projection prologue that initializes visible bindings, and the names
/// to remove from scope after the arm.
const ArmBindings = struct {
    slot: ?typed.LocalId = null,
    prologue: []const typed.StatementId = &.{},
    names: []const []const u8 = &.{},
    fields: []const ?typed.LocalId = &.{},
};
/// `borrowed` is true when the matched value is a named local: a copyable payload
/// then borrows from that local. A payload that transfers (a resource, or a result
/// obligation) is owned by its binding, and so is one a call result owns.
fn bindArmPayload(comptime Checker: type, self: *Checker, case_schema: typed.Variant, arm: ast.MatchArm, borrowed: bool) Error!ArmBindings {
    if (case_schema.fielded) return bindFieldedPayload(Checker, self, case_schema, arm);
    const payload = case_schema.payload;
    if (arm.bindings.len > 1) return self.sink.failRelated(
        ePatternPayload,
        arm.name,
        "a single-payload case binds one name",
        .{ .span = case_schema.declaration, .message = variantDeclaredHere },
    );
    const discards_payload = arm.bindings.len == 1 and arm.bindings[0] == null;
    if (discards_payload and payload != null and self.requiresHandling(payload.?)) return self.sink.failOwnership(.{ .code = eResultDiscard, .rule = .L1 }, arm.name, "nested result payload requires a binding and explicit handling");
    if (payload != null and case_payload.bare(self.src, arm)) return case_payload.refuse(self.src, self.sink, ePatternPayload, arm, .{
        .payload = try typed.surfaceTypeName(self.allocator, payload.?, self.catalog.records),
        .droppable = !self.requiresHandling(payload.?),
        .declared = case_schema.declaration,
    });
    if ((payload != null) != (arm.bindings.len == 1)) return self.sink.failRelated(
        ePatternPayload,
        arm.name,
        "payload variants require a binding or (discard); empty variants take neither",
        .{ .span = case_schema.declaration, .message = variantDeclaredHere },
    );
    if (arm.bindings.len == 0) return .{};
    const binding = arm.bindings[0] orelse return .{};
    const internal = arm.internal.names.len != 0 and arm.internal.names[0].len != 0;
    const name = if (internal) arm.internal.names[0] else self.src.text(binding);
    if (!internal) if (try self.topLevel(binding) or self.active.contains(name)) return self.refuseShadowing(binding, "payload binding");
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{ .initialized = true, .transfer_available = self.transfers(payload.?) },
        .name = name,
        .usage = .{ .temporary = internal },
        .origin = if (borrowed and !self.transfers(payload.?)) .pattern else .local,
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
    if (case_payload.bare(self.src, arm)) {
        const names = try self.allocator.alloc([]const u8, record.fields.len);
        const types = try self.allocator.alloc([]const u8, record.fields.len);
        for (record.fields, names, types) |field, *name, *ty| {
            name.* = field.name;
            ty.* = try typed.surfaceTypeName(self.allocator, field.ty, self.catalog.records);
        }
        return case_payload.refuse(self.src, self.sink, eNamedPattern, arm, .{
            .fields = try case_payload.Fields.of(self.allocator, names, types),
            .droppable = !self.requiresHandling(payload),
            .declared = case_schema.declaration,
        });
    }
    const labels = try self.allocator.alloc([]const u8, record.fields.len);
    for (record.fields, labels) |field, *label| label.* = field.name;
    const sites = try self.allocator.alloc(source.Span, arm.bindings.len);
    for (arm.bindings, sites, 0..) |binding, *site, position| {
        site.* = if (position < arm.payload_patterns.len) arm.payload_patterns[position].pattern.span else binding orelse arm.name;
    }
    try @import("frontend_named_fields.zig").requirePattern(self.sink, self.src, arm.name, eNamedPattern, .{ .labels = labels, .sites = sites, .names = arm.binding_names });
    var normalized = arm;
    if (arm.binding_names.len != 0) {
        const bindings = try self.allocator.alloc(?source.Span, record.fields.len);
        const internal_names = try self.allocator.alloc([]const u8, record.fields.len);
        @memset(internal_names, "");
        const seen = try self.allocator.alloc(bool, record.fields.len);
        @memset(bindings, null);
        @memset(seen, false);
        for (arm.bindings, arm.binding_names, 0..) |binding, label, position| {
            const name = label orelse return self.sink.fail(eNamedPattern, arm.name, "named enum payload fields require labelled patterns");
            const index = try self.catalog.field(record.id, self.src, name, self.sink);
            if (seen[index]) return self.sink.fail("E_DUPLICATE_FIELD", name, "pattern field is bound more than once");
            seen[index] = true;
            bindings[index] = binding;
            if (arm.internal.names.len != 0) internal_names[index] = arm.internal.names[position];
        }
        for (seen) |present| if (!present) return self.sink.fail(ePatternPayload, arm.name, "pattern must name every enum payload field; use `_` to discard one");
        normalized.bindings = bindings;
        normalized.internal.names = internal_names;
    } else return self.sink.fail(eNamedPattern, arm.name, "named enum payload fields require labelled patterns");
    return bindOrderedFieldedPayload(Checker, self, case_schema, normalized, record);
}
fn bindOrderedFieldedPayload(comptime Checker: type, self: *Checker, case_schema: typed.Variant, arm: ast.MatchArm, record: typed.Record) Error!ArmBindings {
    const payload = case_schema.payload orelse return error.InternalError;
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
        if (self.requiresHandling(payload)) return self.sink.failOwnership(.{ .code = eResultDiscard, .rule = .L1 }, arm.name, "nested result payload requires a binding and explicit handling");
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
    const fields = try self.allocator.alloc(?typed.LocalId, record.fields.len);
    @memset(fields, null);
    var prologue: std.ArrayList(typed.StatementId) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    for (arm.bindings, record.fields, 0..) |binding, field_info, index| {
        const binding_span = binding orelse {
            if (self.requiresHandling(field_info.ty)) return self.sink.failOwnershipRelated(
                .{ .code = eResultDiscard, .rule = .L1 },
                arm.name,
                "discarding this field would drop a result-bearing payload; bind it and handle the result",
                .{ .span = field_info.declaration, .message = "result-bearing field declared here" },
            );
            continue;
        };
        const internal = arm.internal.names.len != 0 and arm.internal.names[index].len != 0;
        const name = if (internal) arm.internal.names[index] else self.src.text(binding_span);
        if (!internal) if (try self.topLevel(binding_span) or self.active.contains(name)) return self.refuseShadowing(binding_span, "payload binding");
        const binding_slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        fields[index] = binding_slot;
        try self.locals.append(self.allocator, .{
            .ownership = .{ .initialized = true, .transfer_available = self.transfers(field_info.ty) },
            .name = name,
            .usage = .{ .temporary = internal },
            .origin = .pattern,
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
    return .{ .slot = slot, .prologue = try prologue.toOwnedSlice(self.allocator), .names = try names.toOwnedSlice(self.allocator), .fields = fields };
}
fn statementYield(comptime Checker: type, self: *Checker, expression: ast.NodeId, span: source.Span) Error!@FieldType(typed.Statement, "data") {
    const context = self.match_yield orelse return self.sink.fail("E_MATCH_EXPRESSION_REMOVED", span, "yield arms were removed; assign a named result or return from a match statement arm");
    const value = if (context.ty) |expected| try self.expressionExpected(expression, expected) else try self.expression(expression);
    const actual = self.nodes.items[@backingInt(value)].ty;
    if (context.ty) |expected| try self.require(actual, expected, span);
    self.match_yield.?.ty = actual;
    self.locals.items[@backingInt(context.slot)].ty = actual;
    self.locals.items[@backingInt(context.slot)].ownership.initialized = true;
    self.locals.items[@backingInt(context.slot)].ownership.transfer_available = self.transfers(actual);
    return .{ .initialize = .{ .slot = context.slot, .value = value } };
}
fn yieldsEveryPath(syntax: ast.Program, id: ast.StatementId) bool {
    return switch (syntax.statements.items[@backingInt(id)].data) {
        .yield_value, .ret, .fail => true,
        .block => |children| blk: {
            if (children.len == 0) break :blk false;
            // A yielded arm value is its final operation, never a loop accumulator.
            for (children[0 .. children.len - 1]) |child| if (syntax.statements.items[@backingInt(child)].data == .yield_value) break :blk false;
            break :blk yieldsEveryPath(syntax, children[children.len - 1]);
        },
        .branch => |branch| yieldsEveryPath(syntax, branch.then_body) and if (branch.else_body) |otherwise| yieldsEveryPath(syntax, otherwise) else false,
        else => false,
    };
}
fn matchExpression(comptime Checker: type, self: *Checker, node: ast.Node) Error!typed.Node {
    const match = node.data.match_expression;
    for (match.arms) |arm| if (!yieldsEveryPath(self.syntax, arm.body)) return self.sink.fail("E_MATCH_YIELD", arm.name, "match expressions were removed; use a match statement whose arms assign a named result or return");
    const saved = self.match_yield;
    defer self.match_yield = saved;
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    const expected = self.expected_types.get(node.span);
    try self.locals.append(self.allocator, .{ .name = "", .declaration = node.span, .ty = expected orelse .unit, .mutable = true, .usage = .{ .temporary = true, .reads = 1 } });
    self.match_yield = .{ .slot = slot, .ty = expected };
    var flow: StatementFlow = .{};
    const data = try statementMatch(Checker, self, .{ .span = node.span, .data = .{ .match = .{ .value = match.value, .arms = match.arms } } }, .{ .value = match.value, .arms = match.arms }, &flow);
    const result_type = self.match_yield.?.ty orelse return self.sink.fail("E_MATCH_YIELD", node.span, "match expressions were removed; use a match statement whose arms assign a named result or return");
    _ = data;
    if (@import("control_expression_migration.zig").nestedSelection(self.syntax, node))
        return .{ .span = node.span, .ty = result_type, .data = .{ .local = slot } };
    const spelling = try @import("control_expression_symbolic.zig").typedSpelling(self.allocator, self.src, node.span, result_type, self.catalog);
    return @import("control_expression_migration.zig").reject(self.src, self.syntax, self.sink, node, spelling);
}
fn completeCases(seen: []const ?source.Span) bool {
    for (seen) |item| if (item == null) return false;
    return true;
}
/// A bare name in the payload of a fielded case that is one of the case's field names binds
/// that field: `case circle(radius)` is `case circle(radius=radius)`. The label is written into
/// the arm, so the rest of checking sees the labelled pattern it already accepts. A bare name
/// that is no field name is unchanged and keeps its positional refusal.
fn nameFieldPayloads(allocator: std.mem.Allocator, src: source.Source, records: []const typed.Record, value_type: typed.Type, input: []const ast.MatchArm) Error![]const ast.MatchArm {
    if (!value_type.isAggregate()) return input;
    const variants = records[value_type.recordIndex()].shape.variants orelse return input;
    var output: ?[]ast.MatchArm = null;
    for (input, 0..) |arm, arm_index| {
        if (arm.payload_patterns.len == 0 or arm.binding_names.len != arm.payload_patterns.len) continue;
        const tag = caseIndex(src, variants, arm.name) orelse continue;
        const case = variants.cases[tag];
        if (!case.fielded) continue;
        const payload = case.payload orelse continue;
        if (!payload.isAggregate()) continue;
        const declared = records[payload.recordIndex()].fields;
        var fields: ?[]ast.PatternField = null;
        var labels: ?[]?source.Span = null;
        for (arm.payload_patterns, 0..) |field, position| {
            if (field.name != null or field.pattern.data != .binding) continue;
            const binding = field.pattern.data.binding orelse continue;
            if (!declaresField(declared, src.text(binding))) continue;
            if (fields == null) {
                fields = try allocator.dupe(ast.PatternField, arm.payload_patterns);
                labels = try allocator.dupe(?source.Span, arm.binding_names);
            }
            fields.?[position].name = binding;
            labels.?[position] = binding;
        }
        const named = fields orelse continue;
        if (output == null) output = try allocator.dupe(ast.MatchArm, input);
        output.?[arm_index].payload_patterns = named;
        output.?[arm_index].binding_names = labels.?;
    }
    return output orelse input;
}
/// A rest marker, `case atom(text, ..)`, stands for a discard of every field the pattern does not name. The discards are
/// written into the arm, labelled with the declared field names, so the rest of checking sees the full pattern it already
/// accepts. The marker is checked against the case it follows: a case with no payload has no fields to ignore.
fn restFields(comptime Checker: type, self: *Checker, value_type: typed.Type, input: []const ast.MatchArm) Error![]const ast.MatchArm {
    if (!value_type.isAggregate()) return input;
    const variants = self.catalog.records[value_type.recordIndex()].shape.variants orelse return input;
    var output: ?[]ast.MatchArm = null;
    for (input, 0..) |arm, arm_index| {
        if (!pattern_alternatives.spellsRest(arm)) continue;
        const tag = caseIndex(self.src, variants, arm.name) orelse continue;
        const filled = try fillRest(Checker, self, variants.cases[tag], arm);
        if (output == null) output = try self.allocator.dupe(ast.MatchArm, input);
        output.?[arm_index] = filled;
    }
    return output orelse input;
}
/// The arm with the fields its rest marker stands for, and those of its nested patterns, discarded by name.
fn fillRest(comptime Checker: type, self: *Checker, case_schema: typed.Variant, arm: ast.MatchArm) Error!ast.MatchArm {
    var filled = arm;
    var fields = try self.allocator.dupe(ast.PatternField, arm.payload_patterns);
    var labels = try self.allocator.dupe(?source.Span, arm.binding_names);
    var bindings = try self.allocator.dupe(?source.Span, arm.bindings);
    // A bare case name in an `is` test (`node is leaf`) stands for the case with any payload, so a case without one is fine.
    if (arm.alternatives.rest and !(arm.alternatives.bare and case_schema.payload == null)) {
        const payload = case_schema.payload orelse return self.sink.failRelated(
            ePatternPayload,
            arm.name,
            "this case has no payload, so there are no fields for `..` to ignore",
            .{ .span = case_schema.declaration, .message = variantDeclaredHere },
        );
        if (case_schema.fielded) {
            const declared = self.catalog.records[payload.recordIndex()].fields;
            for (declared) |field| {
                if (mentionsField(self.src, arm, field.name)) continue;
                fields = try pattern_alternatives.appendField(self.allocator, fields, .{ .name = field.declaration, .pattern = .{ .span = field.declaration, .data = .{ .binding = null } } });
                labels = try pattern_alternatives.appendSpan(self.allocator, labels, field.declaration);
                bindings = try pattern_alternatives.appendSpan(self.allocator, bindings, null);
            }
        } else if (arm.payload_patterns.len == 0) {
            fields = try pattern_alternatives.appendField(self.allocator, fields, .{ .pattern = .{ .span = arm.name, .data = .{ .binding = null } } });
            labels = try pattern_alternatives.appendSpan(self.allocator, labels, null);
            bindings = try pattern_alternatives.appendSpan(self.allocator, bindings, null);
        }
    }
    // A pattern nested in a payload field ends with the marker too: `case Err(Malformed(..))`.
    for (fields) |*field| {
        if (field.pattern.data != .variant) continue;
        const slot = fieldSlotType(Checker, self, case_schema, field.*) orelse continue;
        field.pattern = try fillNested(Checker, self, field.pattern, slot, 0);
    }
    filled.payload_patterns = fields;
    filled.binding_names = labels;
    filled.bindings = bindings;
    return filled;
}
/// The type a payload field of a case holds: the declared field a label names, or the single payload.
fn fieldSlotType(comptime Checker: type, self: *Checker, case_schema: typed.Variant, field: ast.PatternField) ?typed.Type {
    const payload = case_schema.payload orelse return null;
    if (!case_schema.fielded) return payload;
    const label = field.name orelse return null;
    for (self.catalog.records[payload.recordIndex()].fields) |declared| {
        if (std.mem.eql(u8, declared.name, self.src.text(label))) return declared.ty;
    }
    return null;
}
/// A nested pattern with the fields its rest marker stands for discarded by name, and those of the patterns below it.
fn fillNested(comptime Checker: type, self: *Checker, pattern: ast.Pattern, slot: typed.Type, depth: usize) Error!ast.Pattern {
    if (pattern.data != .variant or depth > 32) return pattern;
    const nested = pattern.data.variant;
    if (!nested.rest and !pattern_alternatives.nestedSpellsRest(nested.fields, 0)) return pattern;
    const variants = slotVariants(self.catalog.records, slot) orelse return pattern;
    const tag = caseIndex(self.src, variants, nested.name) orelse return pattern;
    const case_schema = variants.cases[tag];
    var fields = try self.allocator.dupe(ast.PatternField, nested.fields);
    if (nested.rest) {
        const payload = case_schema.payload orelse return self.sink.failRelated(
            ePatternPayload,
            nested.name,
            "this case has no payload, so there are no fields for `..` to ignore",
            .{ .span = case_schema.declaration, .message = variantDeclaredHere },
        );
        if (case_schema.fielded) {
            for (self.catalog.records[payload.recordIndex()].fields) |declared| {
                var named = false;
                for (nested.fields) |field| {
                    if (field.name) |label| named = named or std.mem.eql(u8, self.src.text(label), declared.name);
                }
                if (named) continue;
                fields = try pattern_alternatives.appendField(self.allocator, fields, .{ .name = declared.declaration, .pattern = .{ .span = declared.declaration, .data = .{ .binding = null } } });
            }
        } else if (nested.fields.len == 0) {
            fields = try pattern_alternatives.appendField(self.allocator, fields, .{ .pattern = .{ .span = nested.name, .data = .{ .binding = null } } });
        }
    }
    for (fields) |*field| {
        if (field.pattern.data != .variant) continue;
        const inner = fieldSlotType(Checker, self, case_schema, field.*) orelse continue;
        field.pattern = try fillNested(Checker, self, field.pattern, inner, depth + 1);
    }
    return .{ .span = pattern.span, .data = .{ .variant = .{ .ty = nested.ty, .name = nested.name, .fields = fields } } };
}
/// Whether the arm's pattern already names the declared field: by label, or as a bare name that is the field's own.
fn mentionsField(src: source.Source, arm: ast.MatchArm, name: []const u8) bool {
    for (arm.payload_patterns) |field| {
        const label = field.name orelse continue;
        if (std.mem.eql(u8, src.text(label), name)) return true;
    }
    return false;
}
/// Whether a declared field of a record has this name.
fn declaresField(fields: []const typed.Field, name: []const u8) bool {
    for (fields) |field| if (std.mem.eql(u8, field.name, name)) return true;
    return false;
}
/// A bare name in the payload of an unfielded case (`Some`, `Ok`, `Err`, or a declared
/// single payload) names a case when the payload's own enum or union declares one of
/// that name: `case Err(invalid)` matches the `invalid` case of the error type. A name no
/// such case declares still binds the payload, as `case Some(user)` does. A labelled
/// field never takes a case from its type: `left=low` renames the field, as it always
/// has. Returns the arms unchanged when no payload name is a case, so the common match
/// allocates nothing.
fn casedPayloads(comptime Checker: type, self: *Checker, value_type: typed.Type, input: []const ast.MatchArm) Error![]const ast.MatchArm {
    if (!value_type.isAggregate()) return input;
    const variants = self.catalog.records[value_type.recordIndex()].shape.variants orelse return input;
    var output: ?[]ast.MatchArm = null;
    for (input, 0..) |arm, arm_index| {
        if (arm.payload_patterns.len == 0 or wildcard(self.src, arm)) continue;
        const tag = caseIndex(self.src, variants, arm.name) orelse continue;
        const case = variants.cases[tag];
        // A fielded case names its fields instead: its bare names are field names, not cases.
        if (case.fielded) continue;
        var cased: ?[]ast.PatternField = null;
        for (arm.payload_patterns, 0..) |field, position| {
            if (field.pattern.data != .binding or field.name != null) continue;
            const binding = field.pattern.data.binding orelse continue;
            const slot = slotType(case, position) orelse continue;
            if (caseIndex(self.src, slotVariants(self.catalog.records, slot) orelse continue, binding) == null) continue;
            if (cased == null) cased = try self.allocator.dupe(ast.PatternField, arm.payload_patterns);
            cased.?[position].pattern = .{ .span = field.pattern.span, .data = .{ .variant = .{ .ty = .{ .start = binding.start, .end = binding.start }, .name = binding, .fields = &.{} } } };
        }
        const rewritten = cased orelse continue;
        if (output == null) output = try self.allocator.dupe(ast.MatchArm, input);
        const bindings = try self.allocator.dupe(?source.Span, arm.bindings);
        for (rewritten, bindings) |field, *binding| {
            if (field.pattern.data == .variant) binding.* = null;
        }
        output.?[arm_index] = arm;
        output.?[arm_index].payload_patterns = rewritten;
        output.?[arm_index].bindings = bindings;
    }
    return output orelse input;
}
/// Check one arm's qualifier against the matched type, once for every arm of a match.
fn checkArmQualifier(comptime Checker: type, self: *Checker, value_type: typed.Type, arm: ast.MatchArm) Error!void {
    if (arm.ty.start == arm.ty.end) return;
    if (!arm.internal.labelled) return qualifiedCase(Checker, self, value_type, arm.ty, arm.name);
    const contextual = try variant_calls.contextual(self.src, self.catalog, arm.ty, value_type, self.sink);
    try self.require(contextual orelse try self.ty(arm.ty), value_type, arm.ty);
}
/// The position of a case in a closed case set, by its canonical spelling.
fn caseIndex(src: source.Source, variants: typed.Variants, name: source.Span) ?usize {
    const canonical = prelude.caseName(src.text(name));
    for (variants.cases, 0..) |case, index| if (std.mem.eql(u8, case.name, canonical)) return index;
    return null;
}
/// The declared type a payload slot holds: the payload of an unfielded case.
fn slotType(case: typed.Variant, position: usize) ?typed.Type {
    const payload = case.payload orelse return null;
    return if (position == 0) payload else null;
}
/// The case set a slot's type declares, or null when the slot is not a variant type.
fn slotVariants(records: []const typed.Record, slot: typed.Type) ?typed.Variants {
    if (!slot.isAggregate()) return null;
    return records[slot.recordIndex()].shape.variants;
}
/// The name prefix of a literal match's hidden scrutinee local. A NUL byte keeps it out of
/// every source spelling.
const hidden_scrutinee_prefix = "\x00literal";
/// Whether a match on this type compares its value with literal arms: an integer, `bool`,
/// `str` or `bytes`. Such a value has no cases, so a bare name in its arms is a constant.
fn literalScrutinee(comptime Checker: type, self: *Checker, value_type: typed.Type) bool {
    if (value_type.isInteger() or value_type == .bool) return true;
    const kind = managedKind(Checker, self, value_type) orelse return false;
    return kind == .string or kind == .bytes;
}
/// The managed collection family of an aggregate type, or null for a scalar or a record.
fn managedKind(comptime Checker: type, self: *Checker, value_type: typed.Type) ?ManagedKind {
    if (!value_type.isAggregate()) return null;
    return self.catalog.records[value_type.recordIndex()].collection.kind;
}
/// Whether a type is an enum, a union or a result: a closed set of cases.
fn isVariantType(comptime Checker: type, self: *Checker, value_type: typed.Type) bool {
    return value_type.isAggregate() and self.catalog.records[value_type.recordIndex()].shape.variants != null;
}
/// The names and types the first alternative of the `|` list being checked bound.
const AlternativeTypes = struct {
    group: ?ast.StatementId = null,
    first: source.Span = .{ .start = 0, .end = 0 },
    names: []const []const u8 = &.{},
    types: []const typed.Type = &.{},
};
/// Check that an alternative binds the names the first alternative of its list bound, with the same types: the one
/// body reads them whichever alternative matched. An arm written alone resets the check.
fn alternativeTypes(comptime Checker: type, self: *Checker, state: *AlternativeTypes, arm: ast.MatchArm, bound: ArmBindings) Error!void {
    const group = arm.alternatives.group orelse {
        state.group = null;
        return;
    };
    var names: std.ArrayList([]const u8) = .empty;
    var types: std.ArrayList(typed.Type) = .empty;
    if (bound.slot != null and bound.fields.len == 0) {
        const local = self.locals.items[@backingInt(bound.slot.?)];
        try names.append(self.allocator, local.name);
        try types.append(self.allocator, local.ty);
    }
    for (bound.fields) |field| {
        const id = field orelse continue;
        const local = self.locals.items[@backingInt(id)];
        if (local.name.len == 0 or local.name[0] == 0) continue;
        try names.append(self.allocator, local.name);
        try types.append(self.allocator, local.ty);
    }
    if (state.group == null or state.group.? != group) {
        state.* = .{ .group = group, .first = arm.name, .names = names.items, .types = types.items };
        return;
    }
    for (names.items, types.items) |name, ty| {
        for (state.names, state.types) |other, other_ty| {
            if (!std.mem.eql(u8, name, other) or ty == other_ty) continue;
            const template = "this alternative binds `{s}` as `{s}`, but the first binds it as `{s}`: " ++
                "every alternative of a `|` arm binds the same names with the same types";
            const message = try std.fmt.allocPrint(self.allocator, template, .{ name, try typeSpelling(Checker, self, ty), try typeSpelling(Checker, self, other_ty) });
            return self.sink.failRelated(pattern_alternatives.code, arm.name, message, .{ .span = state.first, .message = "the first alternative" });
        }
    }
}
/// Whether any arm of a match spells a literal alternative.
fn anyLiteralArm(arms: []const ast.MatchArm) bool {
    for (arms) |arm| if (arm.literals.len != 0) return true;
    return false;
}
/// One alternative of a literal arm: a literal or name node, or a bare name the arm spells
/// alone (`case LIMIT:`), which has no parsed node and so keeps its span.
const Alternative = union(enum) { node: ast.NodeId, name: source.Span };
/// The spelling an alternative has, which decides what it may be compared with.
const LiteralForm = enum { integer, boolean, text, bytes, name };
fn alternativeForm(comptime Checker: type, self: *Checker, alternative: Alternative) LiteralForm {
    return switch (alternative) {
        .name => .name,
        .node => |id| switch (self.syntax.nodes.items[@backingInt(id)].data) {
            .integer, .unary => .integer,
            .call, .index => .integer,
            .boolean => .boolean,
            .text => .text,
            .bytes => .bytes,
            else => .name,
        },
    };
}
/// The source spelling of a type for a diagnostic (`typed.surfaceTypeName`): `int`, not the builtin's tag `i64`, and
/// `Box[int]`, not the record's internal name `Box<i64>`.
fn typeSpelling(comptime Checker: type, self: *Checker, value_type: typed.Type) Error![]const u8 {
    return typed.surfaceTypeName(self.allocator, value_type, self.catalog.records);
}
/// What a literal alternative compares by. An integer, bool, str or bytes literal compares by its
/// value (`1` and `0x1` are one value; `"a"` and `"\x61"` are one string). A constant compares by
/// its value when the checker folds it, and otherwise by its declaration. A spelling that is not
/// a value in 128 bits compares by its text.
const LiteralKey = union(enum) { int: i128, boolean: bool, text: []const u8, bytes: []const u8, declaration: usize, spelling: []const u8 };
fn sameKey(a: LiteralKey, b: LiteralKey) bool {
    return switch (a) {
        .int => |value| switch (b) {
            .int => |other| value == other,
            else => false,
        },
        .boolean => |value| switch (b) {
            .boolean => |other| value == other,
            else => false,
        },
        .declaration => |value| switch (b) {
            .declaration => |other| value == other,
            else => false,
        },
        .text => |value| switch (b) {
            .text => |other| std.mem.eql(u8, value, other),
            else => false,
        },
        .bytes => |value| switch (b) {
            .bytes => |other| std.mem.eql(u8, value, other),
            else => false,
        },
        .spelling => |value| switch (b) {
            .spelling => |other| std.mem.eql(u8, value, other),
            else => false,
        },
    };
}
/// The value of an integer spelling (underscores and bases included), or null when it does not
/// fit in 128 bits or is not a valid integer.
fn integerValue(text: []const u8) ?i128 {
    return switch (number_literal.integer(text)) {
        .ok => |parts| blk: {
            const magnitude = number_literal.magnitude(parts) orelse break :blk null;
            break :blk std.math.cast(i128, magnitude);
        },
        .bad => null,
    };
}
/// The identity of a literal node: its decoded value, with a minus sign applied to a negative.
fn literalKey(comptime Checker: type, self: *Checker, id: ast.NodeId) LiteralKey {
    const node = self.syntax.nodes.items[@backingInt(id)];
    return switch (node.data) {
        .text => |decoded| .{ .text = decoded },
        .bytes => |decoded| .{ .bytes = decoded },
        .boolean => |value| .{ .boolean = value },
        .integer => |span| if (integerValue(self.src.text(span))) |value| .{ .int = value } else .{ .spelling = self.src.text(span) },
        .unary => |unary| blk: {
            const operand = self.syntax.nodes.items[@backingInt(unary.operand)];
            if (operand.data != .integer) break :blk .{ .spelling = self.src.text(node.span) };
            const magnitude = integerValue(self.src.text(operand.data.integer)) orelse break :blk .{ .spelling = self.src.text(node.span) };
            break :blk .{ .int = -magnitude };
        },
        .call, .index => if (byte_constants.fold(self.src, self.syntax.nodes.items, id)) |byte| .{ .int = byte } else .{ .spelling = self.src.text(node.span) },
        else => .{ .spelling = self.src.text(node.span) },
    };
}
/// A literal alternative after checking: its typed operand, its identity and its span.
const CheckedAlternative = struct { right: typed.NodeId, key: LiteralKey, span: source.Span };
/// One literal arm of a match: its checked alternatives, its body and its span.
const LiteralCase = struct { alternatives: []const CheckedAlternative, body: ast.StatementId, span: source.Span };
/// A checked alternative already seen, for the duplicate-arm check.
const SeenLiteral = struct { key: LiteralKey, span: source.Span };
/// The validated arms of a literal match: the cases in source order, the wildcard arm if any,
/// and whether a bool match lists both values, which makes the last case the chain's else.
const LiteralArms = struct {
    cases: []const LiteralCase,
    wildcard_body: ?ast.StatementId,
    wildcard_span: source.Span,
    bool_complete: bool,
};
/// The matched value as a literal arm reads it: a local the arms compare by slot.
const Scrutinee = struct { slot: typed.LocalId, ty: typed.Type, span: source.Span };
/// The scrutinee's binding: the local the arms read, the statement that initializes a hidden
/// one (null for a name read in place), and the hidden name to take out of scope afterwards.
const BoundScrutinee = struct { scrutinee: Scrutinee, initialize: ?typed.StatementId, hidden: ?[]const u8 };
/// One checked arm of a literal match: its test (null for the last arm of a complete bool
/// match, which is the chain's final else), and its typed body.
const LiteralBranch = struct { condition: ?typed.NodeId, body: typed.StatementId, terminates: bool };
/// The state every literal arm starts from (the pre-match state), and the continuation the
/// arms that fall through reach. The arms are exclusive, as an enum match's arms are.
const ArmState = struct {
    before: []Pending,
    init_before: []u2,
    match_facts: []const usize,
    continuation: ?[]Pending = null,
    continuation_init: ?[]u2 = null,
};
/// The inputs of a literal match, as the statement dispatcher hands them over.
const LiteralInput = struct {
    stmt: ast.Statement,
    match: @FieldType(@FieldType(ast.Statement, "data"), "match"),
    value: typed.NodeId,
    value_type: typed.Type,
    match_facts: []const usize,
};
/// A fresh typed read of the matched value, one per comparison, so no comparison shares an
/// operand node. The read borrows: a comparison never moves the value.
fn scrutineeRead(comptime Checker: type, self: *Checker, scrutinee: Scrutinee) Error!typed.NodeId {
    self.locals.items[@backingInt(scrutinee.slot)].usage.reads += 1;
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = scrutinee.span, .ty = scrutinee.ty, .data = .{ .local = scrutinee.slot } });
    return id;
}
/// The typed equality test of the matched value against one checked alternative.
fn literalTest(comptime Checker: type, self: *Checker, scrutinee: Scrutinee, alternative: CheckedAlternative) Error!typed.NodeId {
    const left = try scrutineeRead(Checker, self, scrutinee);
    var test_node: typed.Node = .{ .ty = .bool, .span = alternative.span, .data = .unit };
    try self.binaryValue(.{ .op = .eq, .op_span = alternative.span, .left = left, .right = alternative.right }, &test_node);
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, test_node);
    return id;
}
/// The typed condition that holds when the matched value equals one of an arm's alternatives:
/// the alternatives' tests, joined with `or`.
fn literalCondition(comptime Checker: type, self: *Checker, scrutinee: Scrutinee, alternatives: []const CheckedAlternative, span: source.Span) Error!typed.NodeId {
    var condition: ?typed.NodeId = null;
    for (alternatives) |alternative| {
        const test_id = try literalTest(Checker, self, scrutinee, alternative);
        condition = if (condition) |previous| try logicalOr(Checker, self, previous, test_id, span) else test_id;
    }
    return condition orelse error.InternalError;
}
/// The typed `or` of two checked booleans.
fn logicalOr(comptime Checker: type, self: *Checker, left: typed.NodeId, right: typed.NodeId, span: source.Span) Error!typed.NodeId {
    var joined: typed.Node = .{ .ty = .bool, .span = span, .data = .unit };
    try self.binaryValue(.{ .op = .logical_or, .op_span = span, .left = left, .right = right }, &joined);
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, joined);
    return id;
}
/// The alternatives one arm lists: its literal nodes, or the bare name it spells alone.
fn armAlternatives(comptime Checker: type, self: *Checker, arm: ast.MatchArm) Error![]const Alternative {
    if (arm.payload_patterns.len != 0 or arm.bindings.len != 0) return self.sink.fail(eLiteralArm, arm.name, "a literal or constant arm has no payload");
    if (arm.literals.len != 0) {
        const listed = try self.allocator.alloc(Alternative, arm.literals.len);
        for (arm.literals, listed) |id, *slot| slot.* = .{ .node = id };
        return listed;
    }
    if (arm.ty.start != arm.ty.end) return self.sink.fail(eLiteralArm, arm.name, "a constant arm names a constant of this module alone, as `case LIMIT:`; " ++
        "an imported constant is not an arm yet, so compare with `if value == settings.ANSWER:`");
    const listed = try self.allocator.alloc(Alternative, 1);
    listed[0] = .{ .name = arm.name };
    return listed;
}
/// Refuse a literal whose spelling is not the matched type's: an integer in a str match, and so on.
fn requireLiteralForm(comptime Checker: type, self: *Checker, span: source.Span, form: LiteralForm, value_type: typed.Type) Error!void {
    const fits = switch (form) {
        .integer => value_type.isInteger(),
        .boolean => value_type == .bool,
        .text => managedKind(Checker, self, value_type) == ManagedKind.string,
        .bytes => managedKind(Checker, self, value_type) == ManagedKind.bytes,
        .name => true,
    };
    if (fits) return;
    const spelling = switch (form) {
        .integer => "int",
        .boolean => "bool",
        .text => "str",
        .bytes => "bytes",
        .name => "constant",
    };
    const message = try std.fmt.allocPrint(self.allocator, "this {s} arm does not match the matched value, which is `{s}`", .{ spelling, try typeSpelling(Checker, self, value_type) });
    return self.sink.fail(eLiteralArm, span, message);
}
/// Check a bare name in a literal arm. It must name a top-level constant of this module; a local,
/// a parameter, a loop variable or any other non-constant is refused, because `case n:` is not a
/// capture in this language, and a comparison with a variable is written with `if`.
fn checkConstantArm(comptime Checker: type, self: *Checker, name: source.Span, value_type: typed.Type, scrutinee: []const u8) Error!CheckedAlternative {
    const text = self.src.text(name);
    const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
    const declared = if (self.active.contains(text)) null else try constants.lookup(name);
    const index = declared orelse {
        const message = try std.fmt.allocPrint(self.allocator, "an arm names a constant, and `{s}` is not one; to compare with a variable, write `if {s} == {s}:`", .{ text, scrutinee, text });
        return self.sink.fail(eLiteralArm, name, message);
    };
    var out: typed.Node = .{ .ty = .unit, .span = name, .data = .unit };
    try self.checkName(.{ .span = name, .data = .{ .name = name } }, name, &out);
    if (out.ty != value_type) {
        const message = try std.fmt.allocPrint(self.allocator, "constant `{s}` is `{s}`, and the matched value is `{s}`", .{ text, try typeSpelling(Checker, self, out.ty), try typeSpelling(Checker, self, value_type) });
        return self.sink.fail(eLiteralArm, name, message);
    }
    const key: LiteralKey = switch (out.data) {
        .integer => |value| .{ .int = value },
        .boolean => |value| .{ .boolean = value },
        else => .{ .declaration = index },
    };
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, out);
    return .{ .right = id, .key = key, .span = name };
}
/// Check a literal node against the matched type: hint it first, so an integer literal takes
/// that type, then check it as an expression.
fn checkLiteralNode(comptime Checker: type, self: *Checker, id: ast.NodeId, value_type: typed.Type) Error!CheckedAlternative {
    const node = self.syntax.nodes.items[@backingInt(id)];
    // `case ord("+"):` and `case b"+"[0]:` are the number of one byte, typed as the matched value is.
    if (node.data == .call or node.data == .index) {
        const byte = byte_constants.fold(self.src, self.syntax.nodes.items, id) orelse
            return self.sink.fail(eLiteralArm, node.span, "an arm takes `ord` of a one-byte literal or a literal indexed by an integer literal, as `case ord(\"+\"):`");
        _ = integers.cast(value_type, byte) catch return self.sink.fail(eLiteralArm, node.span, "the byte does not fit the matched integer type");
        const right: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = value_type, .data = .{ .integer = byte } });
        return .{ .right = right, .key = literalKey(Checker, self, id), .span = node.span };
    }
    try self.hint(id, value_type);
    if (node.data == .unary) try self.hint(node.data.unary.operand, value_type);
    const right = try self.expression(id);
    return .{ .right = right, .key = literalKey(Checker, self, id), .span = node.span };
}
/// Check one alternative of a literal arm, against the matched type.
fn checkAlternative(comptime Checker: type, self: *Checker, alternative: Alternative, value_type: typed.Type, scrutinee: []const u8) Error!CheckedAlternative {
    switch (alternative) {
        .name => |name| return checkConstantArm(Checker, self, name, value_type, scrutinee),
        .node => |id| {
            const node = self.syntax.nodes.items[@backingInt(id)];
            if (node.data == .name) return checkConstantArm(Checker, self, node.data.name, value_type, scrutinee);
            try requireLiteralForm(Checker, self, node.span, alternativeForm(Checker, self, alternative), value_type);
            return checkLiteralNode(Checker, self, id, value_type);
        },
    }
}
/// Validate a literal match's arms: one case per arm, every alternative checked against the
/// matched type, none repeated by value, `case _` last and only where a bool match does not list
/// both values.
fn literalArms(comptime Checker: type, self: *Checker, stmt: ast.Statement, arms: []const ast.MatchArm, value_type: typed.Type, scrutinee: []const u8) Error!LiteralArms {
    var cases: std.ArrayList(LiteralCase) = .empty;
    var seen: std.ArrayList(SeenLiteral) = .empty;
    var true_seen = false;
    var false_seen = false;
    var wildcard_body: ?ast.StatementId = null;
    var wildcard_span: source.Span = stmt.span;
    for (arms, 0..) |arm, position| {
        if (arm.literals.len == 0 and wildcard(self.src, arm)) {
            if (position + 1 != arms.len) return self.sink.fail(eWildcardArm, arm.name, "`case _` must be the last arm of a match");
            wildcard_body = arm.body;
            wildcard_span = arm.name;
            continue;
        }
        var checked: std.ArrayList(CheckedAlternative) = .empty;
        for (try armAlternatives(Checker, self, arm)) |alternative| {
            const item = try checkAlternative(Checker, self, alternative, value_type, scrutinee);
            for (seen.items) |earlier| if (sameKey(earlier.key, item.key)) return self.sink.failRelated(eDuplicateArm, item.span, "literal repeats an earlier arm", .{ .span = earlier.span, .message = "previous arm" });
            try seen.append(self.allocator, .{ .key = item.key, .span = item.span });
            switch (item.key) {
                .boolean => |value| if (value) {
                    true_seen = true;
                } else {
                    false_seen = true;
                },
                else => {},
            }
            try checked.append(self.allocator, item);
        }
        try cases.append(self.allocator, .{ .alternatives = try checked.toOwnedSlice(self.allocator), .body = arm.body, .span = arm.name });
    }
    const bool_complete = value_type == .bool and true_seen and false_seen;
    if (wildcard_body != null) {
        if (bool_complete) return self.sink.fail(eWildcardArm, wildcard_span, "`case _` is unreachable: True and False both have arms");
    } else if (!bool_complete) {
        const message = if (value_type == .bool)
            "a match on bool must list both True and False, or end with `case _`"
        else
            try std.fmt.allocPrint(self.allocator, "a match on `{s}` must end with `case _`, which covers every other value", .{try typeSpelling(Checker, self, value_type)});
        return self.sink.fail(eIncompleteMatch, stmt.span, message);
    }
    return .{ .cases = try cases.toOwnedSlice(self.allocator), .wildcard_body = wildcard_body, .wildcard_span = wildcard_span, .bool_complete = bool_complete };
}
/// Bind the matched value for the arms to read: a local is read in place, and any other value
/// is initialized once into a hidden local (a view stays a view), which is never moved.
fn bindScrutinee(comptime Checker: type, self: *Checker, stmt: ast.Statement, value: typed.NodeId, value_type: typed.Type) Error!BoundScrutinee {
    const node = self.nodes.items[@backingInt(value)];
    if (node.data == .local and !node.own) return .{ .scrutinee = .{ .slot = node.data.local, .ty = value_type, .span = node.span }, .initialize = null, .hidden = null };
    const name = try std.fmt.allocPrint(self.allocator, "{s}{d}", .{ hidden_scrutinee_prefix, self.locals.items.len });
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{ .initialized = true, .transfer_available = self.transfers(value_type) },
        .name = name,
        .declaration = node.span,
        .ty = value_type,
        .mutable = false,
        .origin = if (isViewValue(self.nodes.items, value)) .view else .local,
    });
    try self.active.put(self.allocator, name, slot);
    const initialize: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = false, .data = .{ .initialize = .{ .slot = slot, .value = value } } });
    return .{ .scrutinee = .{ .slot = slot, .ty = value_type, .span = node.span }, .initialize = initialize, .hidden = name };
}
/// Check one arm body from the pre-match state, then merge it into the continuation the
/// following code sees. A wildcard arm checks no handled results, as an enum wildcard does.
fn literalArmBody(comptime Checker: type, self: *Checker, state: *ArmState, body: ast.StatementId, span: source.Span, first_local: usize, wildcard_arm: bool) Error!CheckedStatement {
    self.option_facts.restore(state.match_facts);
    self.restorePending(state.before);
    self.initRestore(state.init_before);
    const checked = try statement(Checker, self, body);
    if (!checked.terminates) {
        try self.mergeMatchInit(&state.continuation_init);
        if (!wildcard_arm) try self.requireHandled(first_local, span);
        if (state.continuation) |pending| try self.samePending(pending, span, eResultPath) else state.continuation = try self.pendingState(state.before.len);
    }
    return checked;
}
/// Build the `if`/`elif` chain of typed branches, from the last test backwards, each falling
/// through to the rest. The tail is the wildcard arm, or the last case of a complete bool match.
fn literalChain(comptime Checker: type, self: *Checker, branches: []const LiteralBranch, tail_body: typed.StatementId, tail_terminates: bool, span: source.Span) Error!typed.StatementId {
    var tail = tail_body;
    var tail_ends = tail_terminates;
    var index = branches.len;
    while (index > 0) {
        index -= 1;
        const branch = branches[index];
        const condition = branch.condition orelse return error.InternalError;
        const terminates = branch.terminates and tail_ends;
        const rest = tail;
        tail = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = span, .terminates = terminates, .data = .{ .branch = .{ .condition = condition, .then_body = branch.body, .else_body = rest } } });
        tail_ends = terminates;
    }
    return tail;
}
/// Check a match on an int, str, bytes or bool whose arms are literals or constants. Each
/// arm tests the matched value in source order and the first one that holds runs. The arms
/// are exclusive, so each body starts from the state before the match, as an enum arm does.
/// The result is an `if`/`elif` chain of typed branches, checked on the same flow state.
/// `match mut` writes each payload binding back into the place it was read from (C1), so the scrutinee must name one:
/// a local, a field, or a list or dictionary element. A temporary or a call result has no place to write into.
fn requireMatchPlace(comptime Checker: type, self: *Checker, value: typed.NodeId, span: source.Span) Error!void {
    if (dictionaryMatchPlace(Checker, self, value)) return self.sink.failOwnership(
        .{ .code = "E_MATCH_MUT", .rule = .X2 },
        self.nodes.items[@backingInt(value)].span,
        "`match mut` on a dictionary element is not yet supported; " ++
            "match the element with `match d[k]`, and write the updated value back with `d[k] = ...`",
    );
    const node = self.nodes.items[@backingInt(value)];
    switch (node.data) {
        .local, .field, .index, .block_value, .buffer_operation => return,
        else => return self.sink.failOwnership(
            .{ .code = "E_MATCH_MUT", .rule = .X2 },
            span,
            "`match mut` needs a place to write the payload back into: name a local, a field, or a list or dictionary element (`match mut xs[i]:`); bind a call result to a `mut` local first",
        ),
    }
}

/// Dictionary exchange is not lowered for a writable match payload yet. This is
/// a restriction on the place's shape; Core checks the owner's mutability.
fn dictionaryMatchPlace(comptime Checker: type, self: *Checker, value: typed.NodeId) bool {
    return switch (self.nodes.items[@backingInt(value)].data) {
        .buffer_operation => |operation| dictionaryMatchType(Checker, self, self.locals.items[@backingInt(operation.owner)].ty),
        .index => |index| dictionaryMatchType(Checker, self, self.nodes.items[@backingInt(index.base)].ty),
        .block_value => |block| dictionaryMatchPlace(Checker, self, block.value),
        else => false,
    };
}

fn dictionaryMatchType(comptime Checker: type, self: *Checker, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = self.catalog.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .dictionary;
}

/// Whether a match hands its payload bindings their payloads: `match own <name>:` consumes the named owner, and a match on
/// a value no local holds (a call result, a constructor) owns what it matched. A plain match on a local and `match mut`
/// borrow. Core still checks each use; this only lets a consuming loop take such a binding (FX8).
fn consumingMatch(comptime Checker: type, self: *Checker, exclusive: bool, value: typed.NodeId) bool {
    if (exclusive) return false;
    const node = self.nodes.items[@backingInt(value)];
    if (node.own) return true;
    // A field or element place, a slice and a local are borrowed by a plain match.
    return switch (node.data) {
        .call, .invoke, .variant, .record => true,
        else => false,
    };
}

/// Remember the visible payload bindings of a consuming match's arm, for `for x in own binding:`.
fn recordConsumingBindings(comptime Checker: type, self: *Checker, exclusive: bool, value: typed.NodeId, arm: ArmBindings) Error!void {
    if (!consumingMatch(Checker, self, exclusive, value)) return;
    if (arm.slot) |slot| try self.consuming_bindings.put(self.allocator, slot, {});
    for (arm.fields) |field| if (field) |slot| try self.consuming_bindings.put(self.allocator, slot, {});
}

/// Every payload binding of a `match mut` arm is a writable place of the scrutinee's payload (C1).
fn markExclusiveBindings(comptime Checker: type, self: *Checker, arm: ArmBindings) void {
    // A binding is a place of the matched value: borrowed, never a transfer out of the payload (C1).
    if (arm.slot) |slot| markExclusiveBinding(self, slot);
    for (arm.fields) |field| if (field) |slot| markExclusiveBinding(self, slot);
}

fn markExclusiveBinding(self: anytype, slot: typed.LocalId) void {
    const local = &self.locals.items[@backingInt(slot)];
    local.mutable = true;
    local.origin = .pattern;
    local.ownership.transfer_available = false;
}

fn statementLiteralMatch(comptime Checker: type, self: *Checker, input: LiteralInput, flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const stmt = input.stmt;
    if (!literalScrutinee(Checker, self, input.value_type)) {
        const first = for (input.match.arms) |arm| {
            if (arm.literals.len != 0) break arm;
        } else return error.InternalError;
        const message = try std.fmt.allocPrint(self.allocator, "a literal arm needs a match on an int, str, bytes or bool, and this value is `{s}`; " ++
            "its cases are named, so write `case circle:`", .{try typeSpelling(Checker, self, input.value_type)});
        return self.sink.fail(eLiteralArm, first.name, message);
    }
    const scrutinee_text = self.src.text(self.syntax.nodes.items[@backingInt(input.match.value)].span);
    const arms = try literalArms(Checker, self, stmt, input.match.arms, input.value_type, scrutinee_text);
    const bound = try bindScrutinee(Checker, self, stmt, input.value, input.value_type);
    defer if (bound.hidden) |name| {
        _ = self.active.remove(name);
    };
    var state: ArmState = .{ .before = try self.pendingState(self.locals.items.len), .init_before = try self.initSnapshot(), .match_facts = input.match_facts };
    flow.terminates = true;
    var branches: std.ArrayList(LiteralBranch) = .empty;
    for (arms.cases, 0..) |case, position| {
        // The last arm of a complete bool match needs no test: it is the final else.
        const is_else = arms.wildcard_body == null and arms.bool_complete and position + 1 == arms.cases.len;
        const condition: ?typed.NodeId = if (is_else) null else try literalCondition(Checker, self, bound.scrutinee, case.alternatives, case.span);
        const body = try literalArmBody(Checker, self, &state, case.body, stmt.span, self.locals.items.len, false);
        flow.terminates = flow.terminates and body.terminates;
        try branches.append(self.allocator, .{ .condition = condition, .body = body.id, .terminates = body.terminates });
    }
    var tail: LiteralBranch = undefined;
    if (arms.wildcard_body) |arm_body| {
        const body = try literalArmBody(Checker, self, &state, arm_body, stmt.span, self.locals.items.len, true);
        flow.terminates = flow.terminates and body.terminates;
        tail = .{ .condition = null, .body = body.id, .terminates = body.terminates };
    } else {
        tail = branches.pop() orelse return error.InternalError;
    }
    if (state.continuation) |pending| self.restorePending(pending);
    if (state.continuation_init) |init| self.initRestore(init) else self.initRestore(state.init_before);
    const chain = try literalChain(Checker, self, branches.items, tail.body, tail.terminates, stmt.span);
    const children = if (bound.initialize) |initialize| try self.allocator.dupe(typed.StatementId, &.{ initialize, chain }) else try self.allocator.dupe(typed.StatementId, &.{chain});
    return .{ .block = children };
}
/// The checked scrutinee of a match: borrowed when the match lends it (`lentScrutinee`), otherwise an ordinary read.
fn scrutineeValue(comptime Checker: type, self: *Checker, exclusive: bool, value: ast.NodeId) Error!typed.NodeId {
    if (try lentScrutinee(Checker, self, exclusive, value)) return self.borrowedExpression(value);
    return self.expression(value);
}

/// Whether a match lends its scrutinee: `match mut` of a place rooted at a `@linear` owner borrows the owner, which keeps
/// its obligation, and the owner is remembered with the scrutinee's span for the refusal of one left unconsumed (FX8).
fn lentScrutinee(comptime Checker: type, self: *Checker, exclusive: bool, value: ast.NodeId) Error!bool {
    if (!exclusive) return false;
    const owner = @import("linear_rules.zig").linearRoot(Checker, self, value) orelse return false;
    // A plain parameter is a read-only loan (decision LINEAR-LEND): `match mut` would write through it.
    try @import("linear_rules.zig").refuseLoanWrite(self.sink, self.catalog.records, self.locals.items[@backingInt(owner)], self.syntax.nodes.items[@backingInt(value)].span);
    try self.match_lent_owners.put(self.allocator, owner, self.syntax.nodes.items[@backingInt(value)].span);
    return true;
}
fn statementMatch(comptime Checker: type, self: *Checker, stmt: ast.Statement, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    for (match.arms) |arm| try self.invalidateOptions(arm.body);
    const match_facts = try self.option_facts.snapshot(self.allocator);
    defer self.option_facts.restore(match_facts);
    try self.hintOptionOperand(match.value);
    // `match mut place:` writes into the place, which keeps its owner: a `@linear` scrutinee is read as a borrow, so the
    // owner matched this way is still to be consumed after the match (FX8, decision LIN). Other types read as before.
    const value = try scrutineeValue(Checker, self, match.exclusive, match.value);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    const bind_else = bind_or_else.isBindOrElse(match.arms);
    try bind_or_else.requireOperand(self.sink, match.arms, bind_or_else.unwrappable(value_type, self.catalog.records), self.syntax.nodes.items[@backingInt(match.value)].span);
    if (match.exclusive) try requireMatchPlace(Checker, self, value, stmt.span);
    if (match.exclusive) try @import("sealed_rules.zig").checkMatchPlace(Checker, self, value, self.syntax.nodes.items[@backingInt(match.value)].span);
    // `case leaf | blank:` is a list of constants to the parser and a list of cases over an enum or a union.
    const listed_arms = if (isVariantType(Checker, self, value_type)) try pattern_alternatives.splitNames(self.allocator, self.syntax.nodes.items, match.arms) else match.arms;
    if (match.exclusive and (literalScrutinee(Checker, self, value_type) or anyLiteralArm(listed_arms))) {
        return self.sink.failOwnership(.{ .code = "E_MATCH_MUT", .rule = .X2 }, stmt.span, "`match mut` writes the payload back into a place and takes case arms only, not literal arms");
    }
    if (literalScrutinee(Checker, self, value_type) or anyLiteralArm(listed_arms)) return statementLiteralMatch(Checker, self, .{ .stmt = stmt, .match = match, .value = value, .value_type = value_type, .match_facts = match_facts }, flow);
    // Every arm's qualifier is checked here, before arms are grouped: a group is checked
    // through its first arm alone, so a later qualified arm would otherwise go unseen.
    for (listed_arms) |arm| try checkArmQualifier(Checker, self, value_type, arm);
    const named_arms = try nameFieldPayloads(self.allocator, self.src, self.catalog.records, value_type, listed_arms);
    const rest_arms = try restFields(Checker, self, value_type, named_arms);
    try pattern_alternatives.requireSameBindings(self.allocator, self.sink, self.src, rest_arms, match.exclusive);
    const cased_arms = try casedPayloads(Checker, self, value_type, rest_arms);
    // Nested payload patterns become hidden inner matches here, appended to the checker's
    // private copy of the syntax tables: the caller's program is never grown or freed.
    const normalized_arms = try frontend_patterns.normalize(Checker, self, cased_arms);
    const variants = try self.catalog.variants(value_type, stmt.span, self.sink);
    const seen = try self.allocator.alloc(?source.Span, variants.cases.len);
    @memset(seen, null);
    var arms: std.ArrayList(typed.MatchArm) = .empty;
    const before = try self.pendingState(self.locals.items.len);
    const init_before = try self.initSnapshot();
    var continuation: ?[]Pending = null;
    var continuation_init: ?[]u2 = null;
    var alternatives: AlternativeTypes = .{};
    flow.terminates = true;
    for (normalized_arms, 0..) |arm, position| {
        self.option_facts.restore(match_facts);
        self.restorePending(before);
        // Every arm starts from the same pre-match definite-assignment state.
        self.initRestore(init_before);
        if (wildcard(self.src, arm)) {
            if (arm.internal.wildcard and completeCases(seen)) continue;
            if (position + 1 != normalized_arms.len) return self.sink.fail(eWildcardArm, arm.name, "`case _` must be the last arm of a match");
            const body = try statement(Checker, self, arm.body);
            if (!body.terminates) {
                try self.mergeMatchInit(&continuation_init);
                if (continuation) |state| try self.samePending(state, stmt.span, eResultPath) else continuation = try self.pendingState(before.len);
            }
            flow.terminates = flow.terminates and body.terminates;
            try wildcardArms(Checker, self, &arms, .{ .seen = seen, .variants = variants, .name = arm.name }, body.id);
            continue;
        }
        const tag = try armTag(Checker, self, value_type, variants, arm);
        if (seen[tag]) |previous| return self.sink.failRelated("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm", .{ .span = previous, .message = "previous arm" });
        seen[tag] = arm.name;
        const case_schema = variants.cases[tag];
        try refuseBareElse(Checker, self, arm, value, case_schema.payload, match.value);
        const first_local = self.locals.items.len;
        const arm_bindings = try bindArmPayload(Checker, self, case_schema, arm, match.exclusive or self.nodes.items[@backingInt(value)].data == .local);
        try recordConsumingBindings(Checker, self, match.exclusive, value, arm_bindings);
        try alternativeTypes(Checker, self, &alternatives, arm, arm_bindings);
        if (match.exclusive) markExclusiveBindings(Checker, self, arm_bindings);
        defer for (arm_bindings.names) |name| {
            _ = self.active.remove(name);
        };
        var body = try statement(Checker, self, arm.body);
        try bind_or_else.requireLeaves(self.sink, arm, body.terminates, bind_or_else.leaveSpan(self.syntax.statements.items, arm.body));
        const unpack: ?typed.UnpackedArm = if (arm_bindings.fields.len != 0) .{ .fields = arm_bindings.fields, .body = body.id } else null;
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
        try arms.append(self.allocator, .{ .tag = tag, .slot = arm_bindings.slot, .body = body.id, .unpack = unpack });
    }
    for (seen, variants.cases) |covered, variant| if (covered == null) {
        const message = try std.fmt.allocPrint(self.allocator, "match does not handle variant `{s}`; every variant requires an explicit arm", .{variant.name});
        const related: diagnostic.Related = .{ .span = variant.declaration, .message = "unhandled variant declared here" };
        const repair = try splitCaseCopy(Checker, self, .{ .value_type = value_type, .arms = normalized_arms, .seen = seen, .variants = variants }, variant.name);
        if (repair) |edit| {
            try self.sink.appendFix(.{ .code = "E_INCOMPLETE_MATCH", .span = stmt.span, .message = message, .related = related }, edit);
            return error.SourceError;
        }
        return self.sink.failRelated("E_INCOMPLETE_MATCH", stmt.span, message, related);
    };
    if (continuation) |state| self.restorePending(state);
    if (continuation_init) |state| self.initRestore(state) else self.initRestore(init_before);
    return .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.allocator), .exclusive = match.exclusive, .continuation = bind_else } };
}
/// The tag an arm takes: the success or failure case of a bind-or-else, otherwise the case its pattern names.
fn armTag(comptime Checker: type, self: *Checker, value_type: typed.Type, variants: typed.Variants, arm: ast.MatchArm) Error!usize {
    if (arm.alternatives.role == .named) return patternTag(Checker, self, value_type, arm.ty, arm.name, arm.internal.labelled);
    return bind_or_else.roleTag(variants.cases, arm.alternatives.role) orelse error.InternalError;
}
/// What a match over a closed type has settled when it finds a case without an arm.
const MatchState = struct { value_type: typed.Type, arms: []const ast.MatchArm, seen: []const ?source.Span, variants: typed.Variants };
/// The repair for a match that lacks `missing`, a case its enum gained by splitting an older one (`variant_splits`):
/// a copy of the arm of the older case under the new name, which is what the program did before the split.
fn splitCaseCopy(comptime Checker: type, self: *Checker, state: MatchState, missing: []const u8) Error!?diagnostic.Edit {
    const enum_name = self.catalog.records[state.value_type.recordIndex()].name;
    const former = variant_splits.formerly(enum_name, missing) orelse return null;
    for (state.variants.cases, state.seen) |case, covered| {
        if (!std.mem.eql(u8, case.name, former)) continue;
        const head = covered orelse return null;
        for (state.arms) |arm| {
            if (arm.name.start != head.start) continue;
            const body = self.syntax.statements.items[@backingInt(arm.body)].span;
            const edit = try variant_splits.copyArm(self.allocator, self.src, .{ .head = head, .body = body }, missing);
            return edit;
        }
    }
    return null;
}
fn statementDiscard(comptime Checker: type, self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "discard"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    // A bare `g.submit(...)` statement is the one submit position that takes no handle (E1).
    if (stmt.implicit_discard) self.tasks.bare_site = self.syntax.nodes.items[@backingInt(expr)].span;
    defer self.tasks.bare_site = null;
    const value = try self.expression(expr);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    if (typed.linear(value_type, self.catalog.records)) return @import("linear_rules.zig").refuse(self.sink, stmt.span, .discard);
    if (stmt.implicit_discard and value_type != .unit) {
        const message = "a standalone non-unit value requires `_ =` or result handling";
        // A result is left to the reader: discarding it would drop an error.
        if (self.requiresHandling(value_type)) return self.sink.failOwnership(.{ .code = "E_EXPLICIT_DISCARD_REQUIRED", .rule = .L1 }, stmt.span, message);
        return self.sink.failFix("E_EXPLICIT_DISCARD_REQUIRED", stmt.span, message, .{ .span = .{ .start = stmt.span.start, .end = stmt.span.start }, .text = "_ = " });
    }
    return .{ .discard = value };
}
fn statementBranch(comptime Checker: type, self: *Checker, stmt: ast.Statement, branch: @FieldType(@FieldType(ast.Statement, "data"), "branch"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const condition = try self.expression(branch.condition);
    try self.requireNode(condition, .bool, self.syntax.nodes.items[@backingInt(branch.condition)].span, null);
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
    const unit: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = span, .ty = .unit, .data = .unit });
    const value = try frontend_failures.wrapSuccess(Checker, self, unit, span);
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
    const value = try frontend_failures.checkReturn(Checker, self, expr, stmt.span);
    try self.requireHandled(0, stmt.span);
    flow.terminates = true;
    // In a `detach` loop the value is held, the collections are put back, and then the held value is returned.
    const staged = try @import("loop_detach.zig").stage(Checker, self, value, stmt.span);
    const returned = if (staged) |held| held.value else value;
    const data: @FieldType(typed.Statement, "data") = if (self.contract.ensures.len != 0) try self.contractReturn(returned, stmt.span) else .{ .ret = returned };
    return if (staged) |held| leaveStaged(Checker, self, held, data, stmt.span) else data;
}
/// The block of a staged exit (`loop_detach.stage`): the held value and the put-backs, then the exit itself.
fn leaveStaged(comptime Checker: type, self: *Checker, staged: @import("loop_detach.zig").Staged, exit: @FieldType(typed.Statement, "data"), span: source.Span) Error!@FieldType(typed.Statement, "data") {
    const leave: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = exit });
    return .{ .block = try std.mem.concat(self.allocator, typed.StatementId, &.{ staged.statements, &.{leave} }) };
}
/// `assert` traps instead of returning, so it needs no result type and no effect.
/// A rendered message is checked as `str` here but evaluated only on failure,
/// which is why the effect pass exempts its expression from the ceiling.
fn statementAssert(comptime Checker: type, self: *Checker, claim: ast.Assertion) Error!@FieldType(typed.Statement, "data") {
    const condition = try self.expressionExpected(claim.condition, .bool);
    try self.requireNode(condition, .bool, self.syntax.nodes.items[@backingInt(claim.condition)].span, null);
    const message_value = if (claim.value) |value| message: {
        const str_type = self.catalog.names.get("str") orelse return error.InternalError;
        const checked = try self.expressionExpected(value, str_type);
        const found = self.nodes.items[@backingInt(checked)].ty;
        if (found != str_type) {
            // The message of an `assert` is one text expression (F-72): a value of another type says so and names the
            // format string that shows it.
            const found_name = try typed.surfaceTypeName(self.allocator, found, self.catalog.records);
            const text = try std.fmt.allocPrint(self.allocator, "expected str, found {s}: the message of an `assert` is one text; " ++
                "a format string shows another value (`assert ok, f'got {{value}}'`)", .{found_name});
            return self.sink.fail("E_TYPE", self.syntax.nodes.items[@backingInt(value)].span, text);
        }
        break :message checked;
    } else null;
    return .{ .assertion = .{ .condition = condition, .message = claim.message, .message_value = message_value } };
}
/// Whether a checked value is a slice of a source. The view flag sits on the
/// operation at the bottom of the block wrappers a slice lowers through.
fn isViewValue(nodes: []const typed.Node, id: typed.NodeId) bool {
    var current = @backingInt(id);
    var remaining: usize = 16;
    while (remaining != 0) : (remaining -= 1) {
        switch (nodes[current].data) {
            .block_value => |block| current = @backingInt(block.value),
            else => return nodes[current].view or nodes[@backingInt(id)].view,
        }
    }
    return nodes[@backingInt(id)].view;
}
fn statementBinding(comptime Checker: type, self: *Checker, _: ast.Statement, b: @FieldType(@FieldType(ast.Statement, "data"), "binding"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const name = self.src.text(b.name);
    // A bind-or-else `adopt` binding takes the name of the arm's own binding of the payload, which it replaces.
    if (!b.adopt and (try self.topLevel(b.name) or self.active.contains(name)))
        return self.refuseShadowing(b.name, "binding");
    for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, name)) return self.sink.fail(eShadowing, b.name, "binding shadows an active arena name");
    if (!b.initialized) {
        const value_type = try self.ty(b.annotation orelse return error.InternalError);
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .name = name,
            .declaration = b.name,
            .ty = value_type,
            .mutable = b.mutable,
            .ownership = .{ .initialized = false, .transfer_available = false },
        });
        try self.active.put(self.allocator, name, slot);
        return .{ .block = &.{} };
    }
    // Only a `const` binding may take a submitted handle (E1): its initialiser is the one submit position.
    if (!b.mutable) self.tasks.const_site = self.syntax.nodes.items[@backingInt(b.value)].span;
    defer self.tasks.const_site = null;
    var value = if (b.annotation) |annotation| try self.expressionExpected(b.value, try self.ty(annotation)) else try self.expression(b.value);
    // A `mut` binding of `R.unwrap_or(d)` keeps its borrow (D-F71-3): such a local may later be given a place, which it
    // borrows beside the first value (4f), so an owned first value would refuse a program accepted before.
    if (!b.mutable or self.nodes.items[@backingInt(value)].data != .borrow_selection) try self.moveTemporaryElement(b.value, value);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    if (b.annotation) |annotation| try self.requireNode(value, try self.ty(annotation), annotation, null);
    if (b.adopt and own_parameters.managed(self.catalog.records, value_type)) value = try adoptedValue(Checker, self, value, self.syntax.nodes.items[@backingInt(b.value)].span);
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
        .origin = if (self.syntax.nodes.items[@backingInt(b.value)].data == .index) .collection_copy else if (isViewValue(self.nodes.items, value)) .view else .local,
    });
    try self.active.put(self.allocator, name, slot);
    if (value_type == .task_handle) try @import("sema_tasks.zig").recordHandle(Checker, self, slot, value);
    return .{ .initialize = .{ .slot = slot, .value = value } };
}
/// The payload a bind-or-else binding takes over, marked `own` as `mut owned = own items` would be, so Core judges the move.
fn adoptedValue(comptime Checker: type, self: *Checker, value: typed.NodeId, span: source.Span) Error!typed.NodeId {
    const marked = try @import("frontend_failures.zig").ownedValue(Checker, self, value, span);
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, marked);
    return id;
}
fn statementAssignment(comptime Checker: type, self: *Checker, stmt: ast.Statement, a: @FieldType(@FieldType(ast.Statement, "data"), "assignment"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const unbound = !self.active.contains(self.src.text(a.name));
    if (a.op == .set and unbound)
        return self.sink.failFix(diagnostic.binding_declaration, a.name, "assignment requires a declared binding; introduce a writable local with `mut`", .{ .span = .{ .start = a.name.start, .end = a.name.start }, .text = "mut " });
    const slot = try self.resolve(a.name);
    const local = self.locals.items[@backingInt(slot)];
    const assigned = local.ownership.initialized or local.ownership.maybe_initialized;
    try @import("linear_rules.zig").refuseLoanWrite(self.sink, self.catalog.records, local, a.name);
    if (!local.mutable and (assigned or a.op != .set))
        return self.sink.failOwnershipRelated(
            .{ .code = eImmutable, .rule = .B1 },
            a.name,
            "const binding may already be assigned on a path reaching here; assign it exactly once on each path",
            .{ .span = local.declaration, .message = "const binding declared here" },
        );
    try self.requireRebindable(slot, a.name);
    // PY-REPEAT-1: `text *= count` repeats the binding by an integer count.
    if (try self.repeatAssignment(slot, a)) |repeated| return repeated;
    var value = try self.expressionExpected(a.value, self.locals.items[@backingInt(slot)].ty);
    // A `mut` local given `R.unwrap_or(d)` keeps the borrow, as its binding does (D-F71-3): it may borrow its other values.
    const kept_borrow = self.locals.items[@backingInt(slot)].mutable and self.nodes.items[@backingInt(value)].data == .borrow_selection;
    if (a.op == .set and !kept_borrow) try self.moveTemporaryElement(a.value, value);
    if (a.op != .set) {
        try self.requireReadable(slot, a.name);
        const target_type = self.locals.items[@backingInt(slot)].ty;
        try self.requireNode(value, target_type, a.op_span, null);
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
    try self.requireNode(value, self.locals.items[@backingInt(slot)].ty, stmt.span, null);
    // A `match mut` binding (a mutable pattern binding) is a place of the matched value: assigning it writes that place,
    // so it is not re-homed as an owner (C1). An ordinary pattern binding is immutable and never reaches here.
    const place_binding = self.locals.items[@backingInt(slot)].origin == .pattern;
    if (!place_binding and self.transfers(self.locals.items[@backingInt(slot)].ty)) {
        if (self.pendingObligation(self.locals.items[@backingInt(slot)]) and typed.linear(self.locals.items[@backingInt(slot)].ty, self.catalog.records)) {
            const rules = @import("linear_rules.zig");
            if (self.match_lent_owners.get(slot)) |lent| return rules.overwriteLent(self.sink, self.allocator, a.name, self.src.text(a.name), lent);
            return rules.refuse(self.sink, a.name, .overwrite);
        }
        if (self.pendingObligation(self.locals.items[@backingInt(slot)])) return self.sink.failOwnership(.{ .code = "E_RESULT_OVERWRITE", .rule = .L1 }, a.name, "assignment would overwrite an unhandled result-bearing value");
        self.locals.items[@backingInt(slot)].ownership.transfer_available = true;
        self.locals.items[@backingInt(slot)].ownership.transfer_span = null;
    }
    self.locals.items[@backingInt(slot)].usage.writes += 1;
    // A plain reassignment re-homes the value, so its copy provenance follows
    // the new initializer; an indexed read still yields an element copy.
    if (a.op == .set and !place_binding) self.locals.items[@backingInt(slot)].origin = if (self.syntax.nodes.items[@backingInt(a.value)].data == .index) .collection_copy else if (isViewValue(self.nodes.items, value)) .view else .local;
    // A reassignment definitely binds the name on this path.
    self.locals.items[@backingInt(slot)].ownership.initialized = true;
    self.option_facts.forget(@backingInt(slot));
    return if (!local.mutable) .{ .initialize = .{ .slot = slot, .value = value } } else .{ .assign = .{ .slot = slot, .value = value } };
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
        .fail => |expr| blk: {
            const value = try frontend_failures.checkFail(Checker, self, expr, stmt.span);
            try self.requireHandled(0, stmt.span);
            flow.terminates = true;
            // In a `detach` loop the failure is held, the collections are put back, and then it leaves.
            const staged = try @import("loop_detach.zig").stage(Checker, self, value, stmt.span) orelse break :blk .{ .ret = value };
            break :blk try leaveStaged(Checker, self, staged, .{ .ret = staged.value }, stmt.span);
        },
        .yield_value => |value| try statementYield(Checker, self, value, stmt.span),
        .loop_exit => |continuing| try self.statementLoopExit(stmt, continuing, &flow),
        .for_each => |each| try self.statementForEach(stmt, each),
        .for_range => |range| try self.statementForRange(stmt, range),
        .assertion => |claim| try statementAssert(Checker, self, claim),
        .binding => |b| try statementBinding(Checker, self, stmt, b, &flow),
        .assignment => |a| try statementAssignment(Checker, self, stmt, a, &flow),
        .gather_step => |step| try self.statementGatherStep(stmt, step),
    };
    const result: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = flow.terminates, .data = data });
    return .{ .id = result, .terminates = flow.terminates, .looping = flow.looping };
}

test "only a bare case _ with no type and no bindings is the wildcard arm" {
    const src: source.Source = .{ .path = "match.selka", .bytes = "_ Some x", .line_starts = &.{} };
    const none: source.Span = .{ .start = 0, .end = 0 };
    const bare = .{ .ty = none, .bindings = &[_]source.Span{}, .name = source.Span{ .start = 0, .end = 1 } };
    const named = .{ .ty = none, .bindings = &[_]source.Span{}, .name = source.Span{ .start = 2, .end = 6 } };
    const bound = .{ .ty = none, .bindings = &[_]source.Span{.{ .start = 7, .end = 8 }}, .name = source.Span{ .start = 0, .end = 1 } };
    try std.testing.expect(wildcard(src, bare));
    try std.testing.expect(!wildcard(src, named));
    try std.testing.expect(!wildcard(src, bound));
}

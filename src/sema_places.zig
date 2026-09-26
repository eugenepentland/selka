//! Checking of assignment targets: tuple construction and destructuring,
//! record-field assignment and its rebuild path, augmented assignment, and
//! writes into fixed arrays and tables with the negative-index rule. Each check
//! is a free function over the concrete checker type; `Checks` exposes the ones
//! the rest of the checker calls as `self.name(...)`.
const sema_shared = @import("sema_shared.zig");
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const eResultOperation = diagnostic.result_operation;
const eShadowing = diagnostic.shadowing;
const eImmutable = diagnostic.immutable;
const std = @import("std");
const set_lower = @import("set_lower.zig");
const eCollectionMethod = sema_shared.eCollectionMethod;
const eTupleArity = diagnostic.tuple_arity;
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const numeric_surface = @import("numeric_surface.zig");
const arrays = @import("array_literals.zig");
const markerPositionDeclared = sema_shared.markerPositionDeclared;
const value_semantics = @import("value_semantics.zig");
/// Diagnostic code for an assignment whose target cannot be written as spelled.
const eAssignmentTarget = "E_ASSIGNMENT_TARGET";
/// The ordinary binary operator one augmented assignment applies to its operand pair.
fn augmentedOperator(op: ast.AssignmentOp) ast.BinaryOp {
    return switch (op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .python_div,
        .floor_div => .floor_div,
        .rem => .floor_rem,
        .set => .add,
    };
}
const eTextOperator = "E_TEXT_OPERATOR";
/// The accepted spelling beside a rejected tuple arity.
const tuple_arity_alternative = "a tuple has between 2 and 8 elements; declare a record for a larger group";
const FieldDestination = struct { owner: typed.LocalId, index: ?typed.NodeId, value: typed.NodeId, refresh: ?typed.StatementId };
/// One step of an assignment path below the value it rebuilds: a record field,
/// or an element of the fixed array or enum table the path has reached.
const PlaceStep = union(enum) { field: source.Span, element: ast.NodeId };
/// An assignment target that writes inside a fixed array or table: the root it
/// rebuilds — a binding name, or the last list or dictionary slot on the path —
/// and the steps below that root in source order.
const ArrayPlace = struct { root: ast.NodeId, steps: []const PlaceStep };
/// The operator and source value of one element assignment.
const PlaceWrite = struct { op: ast.AssignmentOp, value: ast.NodeId };
/// A fixed-array index after the negative-index rule (`PY-ARRAY-NEGATIVE-1`):
/// the key to read and rebuild with, and whether the backend must still count
/// a negative value from the end.
const ArrayKey = struct { key: typed.NodeId, from_end: bool };
const impl = @This();
/// Bind assignment-target checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Apply `PY-ARRAY-NEGATIVE-1` to one fixed-array index. A table key is an
        /// enumeration member and never negative. A constant in `-N .. -1` is
        /// folded to its position from the start, so `a[-1]` costs what `a[N - 1]`
        /// does; any other index the checker cannot prove non-negative is marked
        /// for the backend to count back from the end.
        pub fn arrayKey(self: *Checker, schema: typed.Array, key: typed.NodeId) Error!ArrayKey {
            return impl.arrayKey(Checker, self, schema, key);
        }
        /// The array place an assignment target names, or null when its path writes
        /// no fixed array or table element and the list, dictionary and record rules
        /// own it. `trailing` is the final index of `target[trailing] = value`, which
        /// the parser keeps apart from the target expression.
        ///
        /// The walk reads declared types only, so it reports nothing: a path it
        /// cannot follow falls back to the ordinary rules and their diagnostics.
        /// A list or dictionary slot on the path is a reference, so the value below
        /// the last such slot is rebuilt from that slot, and everything above it is
        /// an ordinary read of the collection.
        pub fn arrayPlace(self: *Checker, target: ast.NodeId, trailing: ?ast.NodeId) Error!?ArrayPlace {
            return impl.arrayPlace(Checker, self, target, trailing);
        }
        /// Combine one augmented-assignment operand pair with the operator's checked rules.
        pub fn augmented(self: *Checker, op: ast.AssignmentOp, left: typed.NodeId, right: typed.NodeId, span: source.Span) Error!typed.NodeId {
            return impl.augmented(Checker, self, op, left, right, span);
        }
        /// Check an assignment that writes inside a fixed array or table:
        /// `a[i] = v`, `a[i].f = v`, `a[i][j] = v`, `r.cells[i] = v`, `xs[k][j] = v`
        /// and their augmented forms.
        ///
        /// The place is rebuilt from its root with `replace` for each element step and
        /// a record update for each field step, then stored back where it came from:
        /// into the binding, with the store marked as an element write, or into the
        /// list or dictionary slot the path runs through. `a[i] = v` on a local is
        /// therefore exactly `a = replace(a, i, v)`, which the backend writes in
        /// place, and value semantics are those of `replace`: a copy taken earlier
        /// keeps its value. The assigned value is evaluated before the target's
        /// indices, as Python does; an index used to both read and rebuild the path
        /// is evaluated once, and nothing the right-hand side does can be lost,
        /// because a value that could write the binding is computed before the
        /// binding is read.
        pub fn checkArrayPlace(self: *Checker, node: ast.Node, place: ArrayPlace, write: PlaceWrite, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkArrayPlace(Checker, self, node, place, write, temporaries);
        }
        /// Check an assignment to a record field, tuple, or array element path, rebuilding
        /// each enclosing value from the root binding down.
        pub fn checkFieldAssignment(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkFieldAssignment(Checker, self, node, temporaries);
        }
        /// Build a fixed array from a list literal whose context already demands `[N]T`.
        pub fn checkFixedArray(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type, expected: typed.Type) Error!typed.Node {
            return impl.checkFixedArray(Checker, self, node, inputs, temporaries, expected);
        }
        /// Check `values[index] op= value` by reading the slot once, combining the pair with
        /// the operator's ordinary rules and writing the result back through the same slot.
        pub fn checkIndexAugmented(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkIndexAugmented(Checker, self, node, temporaries);
        }
        /// Check one `(a, b)` tuple value. The expected-type rule reaches literals:
        /// a destination that already demands a tuple type checks each element
        /// against its positional type, and any other context infers the element
        /// types and interns their tuple.
        pub fn checkTuple(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type, out: *typed.Node) Error!void {
            return impl.checkTuple(Checker, self, node, inputs, temporaries, out);
        }
        /// Whether a checked integer value can never be negative, from facts the
        /// checker already holds: an unsigned type, a non-negative constant, a
        /// loop counter, a length, and the checked operators that keep a
        /// non-negative pair non-negative (an overflow traps rather than wraps).
        /// A loop counter is immutable (`PY-FOR-REBIND-1`), so the fact holds for
        /// every read of it inside its loop.
        pub fn nonNegative(self: *Checker, id: typed.NodeId, depth: usize) bool {
            return impl.nonNegative(Checker, self, id, depth);
        }
        /// Whether local `slot` is a `mut` fixed-array parameter of the function
        /// being checked. It names the caller's array for the whole call, so an
        /// element write through it reaches the caller.
        pub fn referenceParameter(self: *Checker, slot: typed.LocalId) bool {
            return impl.referenceParameter(Checker, self, slot);
        }
        /// Refuse rebinding a `mut` fixed-array parameter as a whole. The name is
        /// the caller's array, so `values = other` would either silently stay local
        /// (the list rule) or overwrite the caller's array (the element rule); the
        /// program says which it means by writing elements or copying to a local.
        pub fn requireRebindable(self: *Checker, slot: typed.LocalId, name: source.Span) Error!void {
            return impl.requireRebindable(Checker, self, slot, name);
        }
        /// The accepted arity a two-name `for` needs, naming the one-name loop.
        pub fn twoNameLoopMessage(self: *Checker, elements: usize) Error![]const u8 {
            return impl.twoNameLoopMessage(Checker, self, elements);
        }
    };
}
/// Check one `(a, b)` tuple value. The expected-type rule reaches literals:
/// a destination that already demands a tuple type checks each element
/// against its positional type, and any other context infers the element
/// types and interns their tuple.
fn checkTuple(comptime Checker: type, self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type, out: *typed.Node) Error!void {
    if (inputs.len < 2 or inputs.len > 8) return self.sink.fail(eTupleArity, node.span, tuple_arity_alternative);
    const expected = if (self.expected_types.get(node.span)) |demanded| record_layouts.tupleRecord(self.catalog.records, demanded) else null;
    if (expected) |schema| if (schema.fields.len != inputs.len) return self.sink.fail(
        eTupleArity,
        node.span,
        try std.fmt.allocPrint(self.allocator, "this tuple has {d} elements but {s} has {d}; write {d} elements", .{
            inputs.len,
            try typed.surfaceTypeName(self.allocator, schema.id, self.catalog.records),
            schema.fields.len,
            schema.fields.len,
        }),
    );
    const values = try self.allocator.alloc(typed.NodeId, inputs.len);
    const types = try self.allocator.alloc(typed.Type, inputs.len);
    for (inputs, 0..) |input, index| {
        if (expected) |schema| try self.hint(input, schema.fields[index].ty);
        const value = try self.expressionWithTemporaries(input, temporaries);
        const actual = self.nodes.items[@backingInt(value)].ty;
        if (expected) |schema| try self.require(actual, schema.fields[index].ty, self.syntax.nodes.items[@backingInt(input)].span);
        values[index] = value;
        types[index] = if (expected) |schema| schema.fields[index].ty else actual;
    }
    out.ty = if (expected) |schema| schema.id else try self.catalog.tupleType(types);
    const initializers = try self.allocator.alloc(typed.FieldInit, values.len);
    for (initializers, values, 0..) |*initializer, value, index| initializer.* = .{ .index = index, .value = value };
    out.data = .{ .record = initializers };
}
/// Bind the names of a `x, y = value` target list to the positional fields of
/// one tuple value. The value is evaluated once into its own slot before any
/// name is written, which is what makes `a, b = b, a` swap.
fn checkTupleAssignment(comptime Checker: type, self: *Checker, assignment: @FieldType(@FieldType(ast.Node, "data"), "field_assignment"), temporaries: []const typed.Type) Error!typed.Node {
    const target = self.syntax.nodes.items[@backingInt(assignment.target)];
    const names = target.data.tuple;
    const checked = try self.expressionWithTemporaries(assignment.value, temporaries);
    const value_type = self.nodes.items[@backingInt(checked)].ty;
    const schema = record_layouts.tupleRecord(self.catalog.records, value_type) orelse {
        const found = try typed.surfaceTypeName(self.allocator, value_type, self.catalog.records);
        const message = try std.fmt.allocPrint(self.allocator, "a destructuring assignment binds the values of a tuple; `{s}` is not one — bind it with one name instead", .{found});
        return self.sink.fail("E_TYPE", self.nodes.items[@backingInt(checked)].span, message);
    };
    if (schema.fields.len != names.len) return self.sink.fail(eTupleArity, target.span, try destructuringMessage(Checker, self, assignment.value, schema.fields.len));
    const b: collections.Builder(Checker) = .{ .checker = self, .span = target.span };
    var statements: std.ArrayList(typed.StatementId) = .empty;
    const value_slot = try b.local(value_type);
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = value_slot, .value = checked } }));
    for (names, 0..) |target_id, index| {
        const element = try b.node(schema.fields[index].ty, .{ .field = .{ .base = try b.read(value_slot), .index = index } });
        switch (self.syntax.nodes.items[@backingInt(target_id)].data) {
            .name => |name| try bindDestructured(Checker, self, name, element, &statements),
            else => try statements.append(self.allocator, try b.stmt(.{ .discard = try destructuredPlace(Checker, self, target_id, element, temporaries) })),
        }
    }
    return b.block(statements.items, try b.node(.unit, .unit));
}
/// PY-DESTRUCTURE-PLACE-1: write one element of an already-evaluated tuple
/// into an element or field target exactly as `target = value` would, so
/// `a[i], a[j] = a[j], a[i]` swaps. The target's own node is never checked
/// as an expression, so its resolution carries the element in as the
/// assigned value; the target's receiver and indices are evaluated here,
/// after the whole right-hand side, in target order, as Python does.
fn destructuredPlace(comptime Checker: type, self: *Checker, target_id: ast.NodeId, element: typed.NodeId, temporaries: []const typed.Type) Error!typed.NodeId {
    const target = self.syntax.nodes.items[@backingInt(target_id)];
    self.resolved[@backingInt(target_id)] = element;
    try self.resolved_nodes.append(self.allocator, @backingInt(target_id));
    const write = switch (target.data) {
        .field => try checkFieldAssignment(Checker, self, .{ .span = target.span, .data = .{ .field_assignment = .{ .target = target_id, .value = target_id } } }, temporaries),
        .index => |access| if (try arrayPlace(Checker, self, access.base, access.index)) |place|
            try checkArrayPlace(Checker, self, target, place, .{ .op = .set, .value = target_id }, temporaries)
        else
            try self.checkListAccess(target, .{ .base = access.base, .kind = .write, .inputs = try self.allocator.dupe(ast.NodeId, &.{ access.index, target_id }) }, temporaries),
        else => return error.InternalError,
    };
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, write);
    return id;
}
/// The accepted arity a destructuring names, naming the value's source when
/// it is a call so the message tells the reader what returned that many.
fn destructuringMessage(comptime Checker: type, self: *Checker, value: ast.NodeId, elements: usize) Error![]const u8 {
    const node = self.syntax.nodes.items[@backingInt(value)];
    const origin = if (node.data == .call and node.data.call.owner == null)
        try std.fmt.allocPrint(self.allocator, "`{s}` returns {d} values", .{ self.src.text(node.data.call.name), elements })
    else
        try std.fmt.allocPrint(self.allocator, "the value has {d} values", .{elements});
    return std.fmt.allocPrint(self.allocator, "{s}; bind {d} names, or `_` for one you do not need", .{ origin, elements });
}
/// The accepted arity a two-name `for` needs, naming the one-name loop.
fn twoNameLoopMessage(comptime Checker: type, self: *Checker, elements: usize) Error![]const u8 {
    return std.fmt.allocPrint(
        self.allocator,
        "a two-name `for` destructures a two-value tuple; this one has {d} values — bind it with one name and destructure it in the body",
        .{elements},
    );
}
/// Bind one destructuring target: a fresh function-scoped local for a name
/// that is not bound yet, an assignment into the existing binding otherwise,
/// and nothing at all for `_`, which needs no slot and reads no element.
fn bindDestructured(comptime Checker: type, self: *Checker, name: source.Span, value: typed.NodeId, statements: *std.ArrayList(typed.StatementId)) Error!void {
    const text = self.src.text(name);
    if (std.mem.eql(u8, text, "_")) return;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = name };
    const value_type = self.nodes.items[@backingInt(value)].ty;
    if (self.active.get(text)) |slot| {
        if (!self.locals.items[@backingInt(slot)].mutable) return self.sink.fail(eImmutable, name, "this binding cannot be assigned");
        try requireRebindable(Checker, self, slot, name);
        try self.requireArenaAssignment(slot, value);
        if (self.transfers(self.locals.items[@backingInt(slot)].ty)) {
            if (self.pendingObligation(self.locals.items[@backingInt(slot)])) return self.sink.fail("E_RESULT_OVERWRITE", name, "assignment would overwrite an unhandled result-bearing value");
            self.locals.items[@backingInt(slot)].ownership.transfer_available = true;
            self.locals.items[@backingInt(slot)].ownership.transfer_span = null;
        }
        self.locals.items[@backingInt(slot)].usage.writes += 1;
        self.locals.items[@backingInt(slot)].ownership.initialized = true;
        self.locals.items[@backingInt(slot)].ownership.arena_confined = false;
        self.option_facts.forget(@backingInt(slot));
        try statements.append(self.allocator, try b.stmt(.{ .assign = .{ .slot = slot, .value = value } }));
        return;
    }
    if (try self.topLevel(name)) return self.sink.fail(eShadowing, name, "binding shadows an active local or top-level function");
    for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, text)) return self.sink.fail(eShadowing, name, "binding shadows an active arena name");
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{ .initialized = true, .transfer_available = self.transfers(value_type) },
        .name = text,
        .declaration = name,
        .ty = value_type,
        .mutable = true,
    });
    try self.active.put(self.allocator, text, slot);
    try self.requireArenaStore(slot, value);
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = slot, .value = value } }));
}
fn checkFieldAssignment(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
    const assignment = node.data.field_assignment;
    if (self.syntax.nodes.items[@backingInt(assignment.target)].data == .tuple)
        return checkTupleAssignment(Checker, self, assignment, temporaries);
    // PY-ARRAY-WRITE-2: `a[i].f op= v` keeps its operator.
    if (try arrayPlace(Checker, self, assignment.target, null)) |place|
        return checkArrayPlace(Checker, self, node, place, .{ .op = assignment.op, .value = assignment.value }, temporaries);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    var path_fields: std.ArrayList(source.Span) = .empty;
    var root = assignment.target;
    while (self.syntax.nodes.items[@backingInt(root)].data == .field) {
        const field = self.syntax.nodes.items[@backingInt(root)].data.field;
        try path_fields.append(self.allocator, field.name);
        root = field.base;
    }
    const root_node = self.syntax.nodes.items[@backingInt(root)];
    var statements: std.ArrayList(typed.StatementId) = .empty;
    const destination = try fieldDestination(Checker, self, root_node, &statements, temporaries);
    // A field write through a by-name copy is only dead when the binding's
    // value came from a copy and nothing reads the binding afterwards. The
    // right-hand side is checked first: a read of the same binding there is
    // part of the write and does not observe the value just stored.
    const dead_owner: ?typed.LocalId = if (destination.index == null) destination.owner else null;
    var value = destination.value;
    const bases = try self.allocator.alloc(typed.NodeId, path_fields.items.len);
    const indices = try self.allocator.alloc(usize, path_fields.items.len);
    for (0..path_fields.items.len) |i| {
        const name = path_fields.items[path_fields.items.len - i - 1];
        const ty_value = self.nodes.items[@backingInt(value)].ty;
        const schema = try self.catalog.record(ty_value, name, self.sink);
        if (self.transfers(ty_value)) return self.sink.fail(eResultOperation, name, "field assignment requires a copyable record without pending results");
        const field = try self.catalog.field(ty_value, self.src, name, self.sink);
        bases[i] = value;
        indices[i] = field;
        value = try b.node(schema.fields[field].ty, .{ .field = .{ .base = value, .index = field } });
    }
    const expected = self.nodes.items[@backingInt(value)].ty;
    const current = value;
    try self.hint(assignment.value, expected);
    value = try self.expressionWithTemporaries(assignment.value, temporaries);
    if (dead_owner) |owner| {
        const payload = self.narrowedOption(owner);
        const shared = if (payload) |shape| shape.element.isAggregate() and self.catalog.records[shape.element.recordIndex()].isManagedRecord() else false;
        if (!shared) noteDeadRecordWrite(Checker, self, owner, node.span);
    }
    try self.require(self.nodes.items[@backingInt(value)].ty, expected, node.span);
    if (assignment.op == .add and expected.isAggregate() and self.catalog.records[expected.recordIndex()].isCollection() and self.catalog.records[expected.recordIndex()].collection.kind == .list) {
        // `target.items += other` is Python's in-place extend, exactly as it is
        // for a list binding: the field keeps the same list, which every alias
        // observes growing, so nothing is stored back.
        if (destination.index == null) try self.requireArenaStore(destination.owner, value);
        const receiver = try b.local(expected);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = receiver, .value = current } }));
        try statements.append(self.allocator, try b.stmt(.{ .discard = try b.operation(receiver, .extend, try self.allocator.dupe(typed.NodeId, &.{value})) }));
        return b.block(statements.items, try b.node(.unit, .unit));
    }
    if (assignment.op != .set) {
        // `target.field op= value` reads the field through the same once-evaluated
        // destination, then evaluates the right-hand side, combines the pair with
        // the operator's ordinary rules and stores the result, the way Python and
        // the list-slot form `values[i] op= value` do. The combined value is kept
        // in its own slot after the destination is set up, so a narrowed owner's
        // refresh cannot run before the field it reads.
        const combined = try augmented(Checker, self, assignment.op, current, value, node.span);
        if (destination.index == null) try self.requireArenaStore(destination.owner, combined);
        const stored = try b.local(expected);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = stored, .value = combined } }));
        if (destination.refresh) |refresh| try statements.append(self.allocator, refresh);
        value = try b.read(stored);
    } else if (destination.index == null) try self.requireArenaStore(destination.owner, value);
    // The value needs its own slot only to survive the destination refresh: it
    // must be computed before the refresh, which re-reads the binding. A managed
    // record needs no refresh, and its update reads the binding where it stands,
    // so the value can go straight into the update's operand.
    if (destination.refresh != null and assignment.op == .set) {
        const refresh = destination.refresh.?;
        const assigned = try b.local(expected);
        const evaluate_value = try b.stmt(.{ .initialize = .{ .slot = assigned, .value = value } });
        try statements.insert(self.allocator, 0, evaluate_value);
        // Preserve unrelated fields changed through aliases while computing the RHS.
        try statements.append(self.allocator, refresh);
        value = try b.read(assigned);
    }
    var i = bases.len;
    while (i > 0) {
        i -= 1;
        value = try b.node(self.nodes.items[@backingInt(bases[i])].ty, .{ .update = .{
            .base = bases[i],
            .fields = try self.allocator.dupe(typed.FieldInit, &.{.{ .index = indices[i], .value = value }}),
        } });
    }
    if (destination.index == null) if (self.narrowedOption(destination.owner)) |shape| {
        value = try b.node(self.locals.items[@backingInt(destination.owner)].ty, .{ .variant = .{ .tag = shape.some, .value = value } });
    };
    const write = if (destination.index) |index|
        try b.stmt(.{ .discard = try b.operation(destination.owner, .write, &.{ index, value }) })
    else
        try b.stmt(.{ .assign = .{ .slot = destination.owner, .value = value } });
    try statements.append(self.allocator, write);
    return b.block(statements.items, try b.node(.unit, .unit));
}
/// Check `values[index] op= value` by reading the slot once, combining the pair with
/// the operator's ordinary rules and writing the result back through the same slot.
fn checkIndexAugmented(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
    const assignment = node.data.index_assignment;
    if (try arrayPlace(Checker, self, assignment.target, null)) |place|
        return checkArrayPlace(Checker, self, node, place, .{ .op = assignment.op, .value = assignment.value }, temporaries);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    var statements: std.ArrayList(typed.StatementId) = .empty;
    const destination = try fieldDestination(Checker, self, self.syntax.nodes.items[@backingInt(assignment.target)], &statements, temporaries);
    const index = destination.index orelse return self.sink.fail(eAssignmentTarget, node.span, "augmented assignment requires a list slot or dictionary entry");
    const element = self.nodes.items[@backingInt(destination.value)].ty;
    try self.hint(assignment.value, element);
    const right = try self.expressionWithTemporaries(assignment.value, temporaries);
    try self.require(self.nodes.items[@backingInt(right)].ty, element, node.span);
    const combined = try augmented(Checker, self, assignment.op, destination.value, right, node.span);
    const stored = try b.local(element);
    const evaluate_value = try b.stmt(.{ .initialize = .{ .slot = stored, .value = combined } });
    // Python reads the slot first, then evaluates the assigned value and writes back.
    try statements.append(self.allocator, evaluate_value);
    try statements.append(self.allocator, try b.stmt(.{ .discard = try b.operation(destination.owner, .write, &.{ index, try b.read(stored) }) }));
    return b.block(statements.items, try b.node(.unit, .unit));
}
/// Combine one augmented-assignment operand pair with the operator's checked rules.
fn augmented(comptime Checker: type, self: *Checker, op: ast.AssignmentOp, left: typed.NodeId, right: typed.NodeId, span: source.Span) Error!typed.NodeId {
    const left_type = self.nodes.items[@backingInt(left)].ty;
    if (numeric_surface.isFloat(left_type, self.catalog.records)) {
        const builder = self.numericBuilder(span);
        return builder.append(try builder.binary(augmentedOperator(op), left, right, self.sink));
    }
    if (left_type.isAggregate() and self.catalog.records[left_type.recordIndex()].isCollection()) {
        const sequence = self.catalog.records[left_type.recordIndex()].collection.kind;
        if (typed.isSet(self.catalog.records[left_type.recordIndex()]))
            return self.sink.fail(set_lower.bitwise_code, span, "a set has no augmented assignment; write `s = s - t`, `s = s | t`, or call `s.update(t)`");
        if (op != .add or sequence == .dictionary) return self.sink.fail(eTextOperator, span, "a managed collection augments with `+=` only, and str, bytes and list are the types that support it");
    } else {
        try self.requireInteger(left_type, span);
        if (op == .div) return self.sink.fail("E_TYPE", span, "augmented `/=` produces a float; declare the binding as float or use `//=`");
    }
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    return b.node(left_type, .{ .binary = .{
        .op = std.meta.stringToEnum(typed.BinaryOp, @tagName(augmentedOperator(op))).?,
        .left = left,
        .right = right,
        .op_span = span,
    } });
}
/// Record a candidate dead field write on a named binding whose value came
/// from a copy (a parameter, iteration variable, or indexed element). The
/// warning is emitted later when no read follows the most recent write.
fn noteDeadRecordWrite(comptime Checker: type, self: *Checker, slot: typed.LocalId, span: source.Span) void {
    const local = &self.locals.items[@backingInt(slot)];
    if (local.origin == .local) return;
    if (!local.ty.isAggregate()) return;
    // VALUE-SEMANTICS-4: a write through a `for` variable is its own error
    // (`E_VALUE_BINDING_WRITE`), and a `mut` record parameter is the caller's
    // record, so its field writes are observed.
    if (value_semantics.enabled() and local.origin == .iteration) return;
    if (local.origin == .parameter and referenceRecordParameter(Checker, self, slot)) return;
    // A managed record (`class` or Cell) is shared, so a field write reaches
    // the original; only copied value `record`s can have dead writes.
    if (self.catalog.records[local.ty.recordIndex()].managed) return;
    if (self.catalog.records[local.ty.recordIndex()].isCollection()) return;
    local.usage.dead_write_reads = local.usage.reads;
    local.usage.dead_write_span = span;
}
fn fieldDestination(comptime Checker: type, self: *Checker, root: ast.Node, statements: *std.ArrayList(typed.StatementId), temporaries: []const typed.Type) Error!FieldDestination {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = root.span };
    if (root.data == .name) {
        const owner = try self.resolve(root.data.name);
        try self.requireReadable(owner, root.data.name);
        if (!self.locals.items[@backingInt(owner)].mutable) return self.sink.fail(eImmutable, root.span, "record field assignment requires a mutable binding");
        self.locals.items[@backingInt(owner)].usage.writes += 1;
        self.locals.items[@backingInt(owner)].usage.reads += 1;
        const owner_type = self.locals.items[@backingInt(owner)].ty;
        if (self.narrowedOption(owner)) |shape| {
            const projected = try option_flow.payloadValue(self, try b.read(owner), shape, root.span);
            const projected_id = try b.node(projected.ty, projected.data);
            const saved = try b.local(shape.element);
            const refresh = try b.stmt(.{ .initialize = .{ .slot = saved, .value = projected_id } });
            try statements.append(self.allocator, refresh);
            return .{ .owner = owner, .index = null, .value = try b.read(saved), .refresh = refresh };
        }
        // A managed record is a reference-identity cell, and `update_record`
        // lowers to an in-place mutation that stores the same pointer back, so
        // the binding never needs copying: the update reads the binding where it
        // stands, after the right-hand side, which is exactly the value the
        // refreshed copy would have held.
        if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isManagedRecord())
            return .{ .owner = owner, .index = null, .value = try b.read(owner), .refresh = null };
        const saved = try b.local(owner_type);
        const refresh = try b.stmt(.{ .initialize = .{ .slot = saved, .value = try b.read(owner) } });
        try statements.append(self.allocator, refresh);
        return .{ .owner = owner, .index = null, .value = try b.read(saved), .refresh = refresh };
    }
    if (root.data != .index) return self.sink.fail(eAssignmentTarget, root.span, "field assignment requires a mutable local record or list slot");
    const access = root.data.index;
    const base = try self.expressionWithTemporaries(access.base, temporaries);
    const ty_value = self.nodes.items[@backingInt(base)].ty;
    if (!self.collectionType(ty_value)) return self.sink.fail(eCollectionMethod, root.span, "indexed field assignment requires a list, dictionary or fixed array reached from a variable");
    const schema = self.catalog.records[ty_value.recordIndex()];
    if (schema.collection.kind == .string or schema.collection.kind == .bytes) return self.sink.fail(eCollectionMethod, root.span, "str and bytes are immutable");
    if (typed.isSet(schema)) return self.sink.fail(set_lower.index_code, root.span, "a set is not indexable; add an element with `s.add(x)`");
    const element = schema.shape.buffer.?;
    const owner = try b.local(ty_value);
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = base } }));
    const index_value = try self.expressionWithTemporaries(access.index, temporaries);
    const dictionary = self.catalog.records[ty_value.recordIndex()].collection.kind == .dictionary;
    const key_type = if (dictionary) self.catalog.records[ty_value.recordIndex()].collection.key.? else typed.Type.i64;
    const index_slot = try b.local(key_type);
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = index_slot, .value = if (dictionary) index_value else try b.index(owner, index_value, false) } }));
    const index = try b.read(index_slot);
    const saved = try b.local(element);
    const refresh = try b.stmt(.{ .initialize = .{ .slot = saved, .value = try b.operation(owner, .read, &.{index}) } });
    try statements.append(self.allocator, refresh);
    return .{ .owner = owner, .index = index, .value = try b.read(saved), .refresh = refresh };
}
/// Whether local `slot` is a `mut` fixed-array parameter of the function
/// being checked. It names the caller's array for the whole call, so an
/// element write through it reaches the caller.
fn referenceParameter(comptime Checker: type, self: *Checker, slot: typed.LocalId) bool {
    if (self.current_lambda != null) return false;
    const id = self.current_function orelse return false;
    const index = @backingInt(slot);
    const signature = self.syntaxFunction(id).signature;
    if (index >= signature.parameters.len or !markerPositionDeclared(signature.mut_positions, @intCast(index))) return false;
    return typed.referenceArray(self.catalog.records, self.locals.items[index].ty);
}
/// Whether local `slot` is a `mut` record parameter that names the caller's
/// record (value semantics only, `VALUE-SEMANTICS-3`).
fn referenceRecordParameter(comptime Checker: type, self: *Checker, slot: typed.LocalId) bool {
    if (self.current_lambda != null) return false;
    const id = self.current_function orelse return false;
    const index = @backingInt(slot);
    const signature = self.syntaxFunction(id).signature;
    if (index >= signature.parameters.len or !markerPositionDeclared(signature.mut_positions, @intCast(index))) return false;
    return typed.referenceRecord(self.catalog.records, self.locals.items[index].ty);
}
/// Refuse rebinding a `mut` fixed-array parameter as a whole. The name is
/// the caller's array, so `values = other` would either silently stay local
/// (the list rule) or overwrite the caller's array (the element rule); the
/// program says which it means by writing elements or copying to a local.
fn requireRebindable(comptime Checker: type, self: *Checker, slot: typed.LocalId, name: source.Span) Error!void {
    if (!referenceParameter(Checker, self, slot)) return;
    const text = self.src.text(name);
    return self.sink.fail(eAssignmentTarget, name, try std.fmt.allocPrint(
        self.allocator,
        "`{s}` is a `mut` array parameter and names the caller's array; write its elements (`{s}[i] = value`), or copy it into a local first",
        .{ text, text },
    ));
}
/// The array place an assignment target names, or null when its path writes
/// no fixed array or table element and the list, dictionary and record rules
/// own it. `trailing` is the final index of `target[trailing] = value`, which
/// the parser keeps apart from the target expression.
///
/// The walk reads declared types only, so it reports nothing: a path it
/// cannot follow falls back to the ordinary rules and their diagnostics.
/// A list or dictionary slot on the path is a reference, so the value below
/// the last such slot is rebuilt from that slot, and everything above it is
/// an ordinary read of the collection.
fn arrayPlace(comptime Checker: type, self: *Checker, target: ast.NodeId, trailing: ?ast.NodeId) Error!?ArrayPlace {
    var chain: std.ArrayList(ast.NodeId) = .empty;
    var cursor = target;
    while (true) switch (self.syntax.nodes.items[@backingInt(cursor)].data) {
        .field => |field| {
            try chain.append(self.allocator, cursor);
            cursor = field.base;
        },
        .index => |index| {
            try chain.append(self.allocator, cursor);
            cursor = index.base;
        },
        .name => break,
        else => return null,
    };
    const slot = self.active.get(self.src.text(self.syntax.nodes.items[@backingInt(cursor)].data.name)) orelse return null;
    var reached = self.locals.items[@backingInt(slot)].ty;
    const count = chain.items.len + @intFromBool(trailing != null);
    const steps = try self.allocator.alloc(PlaceStep, count);
    var root = cursor;
    var first: usize = 0;
    var element_below = false;
    for (steps, 0..) |*step, position| {
        const id: ?ast.NodeId = if (position < chain.items.len) chain.items[chain.items.len - 1 - position] else null;
        if (!reached.isAggregate()) return null;
        const record = self.catalog.records[reached.recordIndex()];
        if (id) |node_id| if (self.syntax.nodes.items[@backingInt(node_id)].data == .field) {
            const name = self.syntax.nodes.items[@backingInt(node_id)].data.field.name;
            if (!record.isRecord() or record.shape.tuple) return null;
            const index = self.catalog.field_names.items[reached.recordIndex()].get(self.src.text(name)) orelse return null;
            step.* = .{ .field = name };
            reached = record.fields[index].ty;
            continue;
        };
        step.* = .{ .element = if (id) |node_id| self.syntax.nodes.items[@backingInt(node_id)].data.index.index else trailing.? };
        if (record.shape.array) |array| {
            element_below = true;
            reached = array.element;
            continue;
        }
        if (!record.isCollection()) return null;
        if (record.collection.kind != .list and record.collection.kind != .dictionary) return null;
        if (record.collection.set) return null;
        root = id orelse return null;
        first = position + 1;
        element_below = false;
        reached = record.shape.buffer.?;
    }
    if (!element_below) return null;
    return .{ .root = root, .steps = steps[first..] };
}
/// Whether a checked value can neither trap nor have an effect, so when it
/// is evaluated relative to the rest of an assignment cannot be observed.
fn inertValue(comptime Checker: type, self: *Checker, id: typed.NodeId) bool {
    return switch (self.nodes.items[@backingInt(id)].data) {
        .integer, .boolean, .unit, .local => true,
        else => false,
    };
}
/// Whether a checked value has no effect other than a possible trap, so it
/// may be evaluated twice — once to read a path, once to rebuild it — and
/// cannot write the binding an element assignment is rebuilding.
fn effectFreeValue(comptime Checker: type, self: *Checker, id: typed.NodeId, depth: usize) bool {
    if (depth == 16) return false;
    return switch (self.nodes.items[@backingInt(id)].data) {
        .integer, .boolean, .unit, .local => true,
        .binary => |binary| effectFreeValue(Checker, self, binary.left, depth + 1) and effectFreeValue(Checker, self, binary.right, depth + 1),
        .unary => |unary| effectFreeValue(Checker, self, unary.operand, depth + 1),
        .field => |field| effectFreeValue(Checker, self, field.base, depth + 1),
        .index => |index| effectFreeValue(Checker, self, index.base, depth + 1) and effectFreeValue(Checker, self, index.index, depth + 1),
        .cast => |operand| effectFreeValue(Checker, self, operand, depth + 1),
        else => false,
    };
}
/// The value of a checked integer constant index, `k` or `-k`.
fn constantIndex(comptime Checker: type, self: *Checker, id: typed.NodeId) ?i128 {
    return switch (self.nodes.items[@backingInt(id)].data) {
        .integer => |value| value,
        .unary => |unary| if (unary.op == .neg) switch (self.nodes.items[@backingInt(unary.operand)].data) {
            .integer => |value| -value,
            else => null,
        } else null,
        else => null,
    };
}
/// Whether a checked integer value can never be negative, from facts the
/// checker already holds: an unsigned type, a non-negative constant, a
/// loop counter, a length, and the checked operators that keep a
/// non-negative pair non-negative (an overflow traps rather than wraps).
/// A loop counter is immutable (`PY-FOR-REBIND-1`), so the fact holds for
/// every read of it inside its loop.
fn nonNegative(comptime Checker: type, self: *Checker, id: typed.NodeId, depth: usize) bool {
    if (depth == 8) return false;
    const node = self.nodes.items[@backingInt(id)];
    if (node.ty.integer()) |info| if (!info.signed) return true;
    return switch (node.data) {
        .integer => |value| value >= 0,
        .length => true,
        .buffer_operation => |operation| operation.kind == .length,
        // `len(xs)` roots its receiver in a block around the length read.
        .block_value => |block| nonNegative(Checker, self, block.value, depth + 1),
        .cast => |operand| nonNegative(Checker, self, operand, depth + 1),
        .local => |slot| self.counters.contains(slot),
        .binary => |binary| switch (binary.op) {
            .add, .mul, .div, .floor_div, .rem => nonNegative(Checker, self, binary.left, depth + 1) and nonNegative(Checker, self, binary.right, depth + 1),
            // Python's `%` takes the divisor's sign.
            .floor_rem => if (constantIndex(Checker, self, binary.right)) |divisor| divisor > 0 else nonNegative(Checker, self, binary.left, depth + 1) and nonNegative(Checker, self, binary.right, depth + 1),
            .bit_and => nonNegative(Checker, self, binary.left, depth + 1) or nonNegative(Checker, self, binary.right, depth + 1),
            .shift_right => nonNegative(Checker, self, binary.left, depth + 1),
            else => false,
        },
        else => false,
    };
}
/// Apply `PY-ARRAY-NEGATIVE-1` to one fixed-array index. A table key is an
/// enumeration member and never negative. A constant in `-N .. -1` is
/// folded to its position from the start, so `a[-1]` costs what `a[N - 1]`
/// does; any other index the checker cannot prove non-negative is marked
/// for the backend to count back from the end.
fn arrayKey(comptime Checker: type, self: *Checker, schema: typed.Array, key: typed.NodeId) Error!ArrayKey {
    if (schema.key != null) return .{ .key = key, .from_end = false };
    if (constantIndex(Checker, self, key)) |value| {
        if (value >= 0) return .{ .key = key, .from_end = false };
        const length: i128 = @intCast(schema.length);
        if (value < -length) return .{ .key = key, .from_end = true };
        const b: collections.Builder(Checker) = .{ .checker = self, .span = self.nodes.items[@backingInt(key)].span };
        return .{ .key = try b.node(.i64, .{ .integer = value + length }), .from_end = false };
    }
    return .{ .key = key, .from_end = !nonNegative(Checker, self, key, 0) };
}
/// Evaluate `value` into a fresh temporary now, answering a read of it.
fn spillValue(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), value: typed.NodeId, statements: *std.ArrayList(typed.StatementId)) Error!typed.NodeId {
    const slot = try b.local(self.nodes.items[@backingInt(value)].ty);
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = slot, .value = value } }));
    return b.read(slot);
}
/// Check an assignment that writes inside a fixed array or table:
/// `a[i] = v`, `a[i].f = v`, `a[i][j] = v`, `r.cells[i] = v`, `xs[k][j] = v`
/// and their augmented forms.
///
/// The place is rebuilt from its root with `replace` for each element step and
/// a record update for each field step, then stored back where it came from:
/// into the binding, with the store marked as an element write, or into the
/// list or dictionary slot the path runs through. `a[i] = v` on a local is
/// therefore exactly `a = replace(a, i, v)`, which the backend writes in
/// place, and value semantics are those of `replace`: a copy taken earlier
/// keeps its value. The assigned value is evaluated before the target's
/// indices, as Python does; an index used to both read and rebuild the path
/// is evaluated once, and nothing the right-hand side does can be lost,
/// because a value that could write the binding is computed before the
/// binding is read.
fn checkArrayPlace(comptime Checker: type, self: *Checker, node: ast.Node, place: ArrayPlace, write: PlaceWrite, temporaries: []const typed.Type) Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const root_node = self.syntax.nodes.items[@backingInt(place.root)];
    var root_statements: std.ArrayList(typed.StatementId) = .empty;
    var owner: typed.LocalId = undefined;
    var slot_index: ?typed.NodeId = null;
    var current: typed.NodeId = undefined;
    if (root_node.data == .name) {
        owner = try self.resolve(root_node.data.name);
        try self.requireReadable(owner, root_node.data.name);
        const local = &self.locals.items[@backingInt(owner)];
        if (!local.mutable) return self.sink.fail(eImmutable, root_node.span, "element assignment requires a mutable binding");
        if (self.transfers(local.ty)) return self.sink.fail(eResultOperation, root_node.span, "element assignment requires a copyable value without pending results");
        local.usage.writes += 1;
        local.usage.reads += 1;
        current = try b.read(owner);
    } else {
        const destination = try fieldDestination(Checker, self, root_node, &root_statements, temporaries);
        owner = destination.owner;
        slot_index = destination.index;
        current = destination.value;
    }
    const bases = try self.allocator.alloc(typed.NodeId, place.steps.len);
    const keys = try self.allocator.alloc(ArrayKey, place.steps.len);
    const members = try self.allocator.alloc(usize, place.steps.len);
    var key_statements: std.ArrayList(typed.StatementId) = .empty;
    var keys_inert = true;
    for (place.steps, 0..) |step, i| {
        bases[i] = current;
        const base_type = self.nodes.items[@backingInt(current)].ty;
        switch (step) {
            .field => |name| {
                const schema = try self.catalog.record(base_type, name, self.sink);
                if (self.transfers(base_type)) return self.sink.fail(eResultOperation, name, "field assignment requires a copyable record without pending results");
                members[i] = try self.catalog.field(base_type, self.src, name, self.sink);
                current = try b.node(schema.fields[members[i]].ty, .{ .field = .{ .base = current, .index = members[i] } });
            },
            .element => |key_node| {
                const key_span = self.syntax.nodes.items[@backingInt(key_node)].span;
                const schema = try self.catalog.array(base_type, key_span, self.sink);
                if (self.requiresHandling(schema.element)) return self.sink.fail(eResultOperation, node.span, "replacement would drop an unhandled result-bearing element");
                if (schema.key) |key| try self.hint(key_node, key);
                const checked = try self.expressionWithTemporaries(key_node, temporaries);
                try self.requireIndex(schema, self.nodes.items[@backingInt(checked)].ty, key_span);
                // PY-ARRAY-NEGATIVE-1: decided on the key as written, then
                // carried by whatever temporary holds it.
                var key = try arrayKey(Checker, self, schema, checked);
                if (!effectFreeValue(Checker, self, key.key, 0)) key.key = try spillValue(Checker, self, b, key.key, &key_statements);
                keys_inert = keys_inert and inertValue(Checker, self, key.key);
                keys[i] = key;
                current = try b.node(schema.element, .{ .index = .{ .base = current, .index = key.key, .from_end = key.from_end } });
            },
        }
    }
    const leaf_type = self.nodes.items[@backingInt(current)].ty;
    try self.hint(write.value, leaf_type);
    const right = try self.expressionWithTemporaries(write.value, temporaries);
    try self.require(self.nodes.items[@backingInt(right)].ty, leaf_type, node.span);
    var statements: std.ArrayList(typed.StatementId) = .empty;
    var value = right;
    if (write.op == .set) {
        // A binding root reads the binding only at the store, so an inert
        // index cannot be reordered against the value; a slot root is read
        // by the statements that locate it, which Python runs after the value.
        const spill = !inertValue(Checker, self, right) and (slot_index != null or !keys_inert or !effectFreeValue(Checker, self, right, 0));
        if (spill) value = try spillValue(Checker, self, b, right, &statements);
        try statements.appendSlice(self.allocator, root_statements.items);
        try statements.appendSlice(self.allocator, key_statements.items);
    } else {
        // Python reads the element, then evaluates the operand, then stores.
        try statements.appendSlice(self.allocator, root_statements.items);
        try statements.appendSlice(self.allocator, key_statements.items);
        value = try augmented(Checker, self, write.op, current, right, node.span);
        if (!effectFreeValue(Checker, self, right, 0)) value = try spillValue(Checker, self, b, value, &statements);
    }
    if (slot_index == null) try self.requireArenaStore(owner, if (write.op == .set) right else value);
    var i = place.steps.len;
    while (i > 0) {
        i -= 1;
        const base_type = self.nodes.items[@backingInt(bases[i])].ty;
        value = switch (place.steps[i]) {
            .field => try b.node(base_type, .{ .update = .{
                .base = bases[i],
                .fields = try self.allocator.dupe(typed.FieldInit, &.{.{ .index = members[i], .value = value }}),
            } }),
            .element => try b.node(base_type, .{ .replace = .{ .base = bases[i], .index = keys[i].key, .value = value, .from_end = keys[i].from_end } }),
        };
    }
    const stored = if (slot_index) |index|
        try b.stmt(.{ .discard = try b.operation(owner, .write, &.{ index, value }) })
    else
        try b.stmt(.{ .assign = .{ .slot = owner, .value = value, .element = true } });
    try statements.append(self.allocator, stored);
    return b.block(statements.items, try b.node(.unit, .unit));
}
/// Build a fixed array from a list literal whose context already demands `[N]T`.
fn checkFixedArray(comptime Checker: type, self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type, expected: typed.Type) Error!typed.Node {
    const shape = arrays.fixed(self.catalog, expected).?;
    if (inputs.len != shape.length) return arrays.wrongLength(self.allocator, node.span, inputs.len, shape, self.sink);
    const values = try self.allocator.alloc(typed.NodeId, inputs.len);
    for (inputs, values) |input, *value| {
        try self.hint(input, shape.element);
        value.* = try self.expressionWithTemporaries(input, temporaries);
        try self.require(self.nodes.items[@backingInt(value.*)].ty, shape.element, self.syntax.nodes.items[@backingInt(input)].span);
    }
    return .{ .span = node.span, .ty = expected, .data = .{ .array = values } };
}

test "augmented assignment follows Python: /= is true division and %= a floored remainder" {
    try std.testing.expectEqual(ast.BinaryOp.python_div, augmentedOperator(.div));
    try std.testing.expectEqual(ast.BinaryOp.floor_div, augmentedOperator(.floor_div));
    try std.testing.expectEqual(ast.BinaryOp.floor_rem, augmentedOperator(.rem));
    try std.testing.expectEqual(ast.BinaryOp.sub, augmentedOperator(.sub));
}

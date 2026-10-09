//! Checking of loops: `while`, `for` over collections, `enumerate`, `reversed`,
//! `zip`, dictionary views and prelude iterables, `for ... in range(...)`, the
//! hidden positions and rebinding a loop variable written in its body needs
//! (`PY-FOR-REBIND-1`), and `break`/`continue`. Each check is a free function
//! over the concrete checker type; `Checks` exposes the ones the rest of the
//! checker calls as `self.name(...)`.
const sema_shared = @import("sema_shared.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const collections = @import("collection_lower.zig");
const loop_rebinding = @import("loop_rebinding.zig");
const call_arguments = @import("call_arguments.zig");
const eShadowing = diagnostic.shadowing;
const eResultLoop = diagnostic.result_loop;
const std = @import("std");
const iteration_place = @import("iteration_place.zig");
const dictionary_views = @import("dictionary_views.zig");
const eCollectionMethod = sema_shared.eCollectionMethod;
const eTupleArity = diagnostic.tuple_arity;
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const prelude_builtins = @import("prelude_builtins.zig");
const arrays = @import("array_literals.zig");
const StatementFlow = sema_shared.StatementFlow;
/// A parsed `for` loop over a collection, `enumerate`, `reversed` or `zip`.
const ForEach = @FieldType(@FieldType(ast.Statement, "data"), "for_each");
const eIterationShadow = "iteration binding shadows an active declaration";
/// How a loop reads its source: a collection kind, a fixed array read by
/// index, or a dictionary view's projection.
const IterationShape = struct { kind: ManagedKind, fixed: ?typed.Array = null, projection: ?@import("dictionary_views.zig").Kind = null };
const impl = @This();
/// Bind loop checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Whether a type is a managed collection a loop can walk by position.
        pub fn collectionType(self: *Checker, candidate: typed.Type) bool {
            return impl.collectionType(Checker, self, candidate);
        }
        /// Read the element at `index` of the loop's source copy in `owner`.
        pub fn iterationRead(self: *Checker, b: collections.Builder(Checker), owner: typed.LocalId, index: typed.NodeId, source_shape: IterationShape) Error!typed.NodeId {
            return impl.iterationRead(Checker, self, b, owner, index, source_shape);
        }
        /// Check a `for` loop over a collection, `enumerate`, `reversed`, `zip`, a dictionary
        /// view or a prelude iterable.
        pub fn statementForEach(self: *Checker, stmt: ast.Statement, each: ForEach) Error!@FieldType(typed.Statement, "data") {
            return impl.statementForEach(Checker, self, stmt, each);
        }
        /// Check `for name in range(...)`, marking a counter that starts non-negative and
        /// rebinding it on a hidden local when the body writes it.
        pub fn statementForRange(self: *Checker, stmt: ast.Statement, range: @FieldType(@FieldType(ast.Statement, "data"), "for_range")) Error!@FieldType(typed.Statement, "data") {
            return impl.statementForRange(Checker, self, stmt, range);
        }
        /// Check a `while` loop: its condition, its body under a new loop scope, and the
        /// same ownership state on every path back to the head.
        pub fn statementLoop(self: *Checker, stmt: ast.Statement, loop: @FieldType(@FieldType(ast.Statement, "data"), "loop"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
            return impl.statementLoop(Checker, self, stmt, loop, flow);
        }
        /// Check `break` or `continue` against the innermost loop's ownership checkpoint.
        pub fn statementLoopExit(self: *Checker, stmt: ast.Statement, continuing: bool, flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
            return impl.statementLoopExit(Checker, self, stmt, continuing, flow);
        }
    };
}
fn statementLoop(comptime Checker: type, self: *Checker, stmt: ast.Statement, loop: @FieldType(@FieldType(ast.Statement, "data"), "loop"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    try self.invalidateOptions(loop.body);
    const loop_facts = try self.option_facts.snapshot(self.allocator);
    defer self.option_facts.restore(loop_facts);
    const before = try self.pendingState(self.locals.items.len);
    const condition = try self.expression(loop.condition);
    try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(loop.condition)].span);
    try self.samePending(before, stmt.span, eResultLoop);
    const loop_id = self.loops.next;
    self.loops.next += 1;
    try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before });
    defer _ = self.loops.active.pop();
    const init_before = try self.initSnapshot();
    try self.assumeOption(loop.condition, true);
    const body = try self.statement(loop.body);
    // A loop may execute zero times, so assignments made only in its body
    // cannot make a pre-existing local definitely assigned after the loop.
    // Locals first introduced in the body remain resolvable by name but
    // report E_UNBOUND until a later assignment on this path initializes them.
    self.initRestore(init_before);
    if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
    self.restorePending(before);
    // `while True:` without a break has no exit, so control never reaches what follows.
    const always = self.nodes.items[@backingInt(condition)].data == .boolean and self.nodes.items[@backingInt(condition)].data.boolean;
    flow.terminates = always and !self.loops.active.items[self.loops.active.items.len - 1].exited;
    flow.looping = flow.terminates;
    return .{ .loop = .{ .id = loop_id, .condition = condition, .body = body.id } };
}
fn statementForEach(comptime Checker: type, self: *Checker, stmt: ast.Statement, each: ForEach) Error!@FieldType(typed.Statement, "data") {
    try self.invalidateOptions(each.body);
    const loop_facts = try self.option_facts.snapshot(self.allocator);
    defer self.option_facts.restore(loop_facts);
    if (try preludeIteration(Checker, self, stmt, each)) |statements| return .{ .block = statements };
    const b: collections.Builder(Checker) = .{ .checker = self, .span = stmt.span };
    const source_value = try self.expression(each.iterable);
    const view = dictionary_views.identify(self.catalog, self.nodes.items[@backingInt(source_value)].ty);
    const projected = view != null and view.? != .item;
    const iterable = if (projected) try dictionary_views.owner(Checker, self, stmt.span, source_value) else source_value;
    const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
    // Fixed arrays have a static bound; their place reads follow D1 too.
    const fixed = arrays.fixed(self.catalog, iterable_type);
    if (fixed == null and !collectionType(Checker, self, iterable_type)) return self.sink.fail(eCollectionMethod, stmt.span, "iteration requires a collection, fixed array or dictionary view");
    const kind = self.catalog.records[iterable_type.recordIndex()].collection.kind;
    const element = try iterationElement(Checker, self, iterable_type, fixed, if (projected) view else null, stmt.span);
    const unpack = each.index_name != null and !each.enumerated;
    if (unpack and dictionary_views.identify(self.catalog, element) != .item) {
        const pair = record_layouts.tupleRecord(self.catalog.records, element) orelse
            return self.sink.fail("E_ITERATION", stmt.span, "two iteration names require dictionary items, enumerate, zip or a list of two-value tuples");
        if (pair.fields.len != 2) return self.sink.fail(eTupleArity, stmt.span, try self.twoNameLoopMessage(pair.fields.len));
    }
    const first_type = if (unpack) self.catalog.records[element.recordIndex()].fields[0].ty else element;
    // PY-ARRAY-ITER-2: a stable fixed-array local is walked in place.
    var source_walk = try beginWalk(Checker, self, b, iterable, fixed);
    const index = try b.local(.i64);
    const limit = try b.local(.i64);
    const first_slot = try b.local(first_type);
    const position = try loopPosition(Checker, self, b, each, index);
    const second_slot = if (unpack) try b.local(self.catalog.records[element.recordIndex()].fields[1].ty) else position.slot;
    const names = discardOnce(self.src, if (unpack) [_]?source.Span{ each.index_name, each.name } else [_]?source.Span{ each.name, each.index_name });
    const slots = [_]typed.LocalId{ first_slot, second_slot };
    for (names) |maybe_name| if (maybe_name) |name| {
        if (try self.shadows(name)) return self.sink.fail(eShadowing, name, eIterationShadow);
    };
    if (each.index_name) |name| if (!isDiscard(self.src, name) and std.mem.eql(u8, self.src.text(name), self.src.text(each.name))) return self.sink.fail(eShadowing, name, "iteration names must differ");
    var hidden = [_]?typed.LocalId{ null, null };
    for (names, slots, &hidden) |maybe_name, slot, *earlier| if (maybe_name) |name| {
        self.locals.items[@backingInt(slot)].mutable = false;
        self.locals.items[@backingInt(slot)].name = self.src.text(name);
        self.locals.items[@backingInt(slot)].declaration = name;
        self.locals.items[@backingInt(slot)].ownership.initialized = true;
        self.locals.items[@backingInt(slot)].origin = .iteration;
        earlier.* = try self.bindScoped(self.src.text(name), slot);
    };
    defer for (names, hidden) |maybe_name, earlier| if (maybe_name) |name| self.unbindScoped(self.src.text(name), earlier);
    const before = try self.pendingState(self.locals.items.len);
    const loop_id = self.loops.next;
    self.loops.next += 1;
    try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before });
    defer _ = self.loops.active.pop();
    const init_before = try self.initSnapshot();
    const body = try self.statement(each.body);
    _ = self.counters.remove(index);
    const owner = try endWalk(Checker, self, b, &source_walk, each.body);
    const prepared = try walkSource(Checker, b, source_walk, iterable, owner, each.body);
    self.initRestore(init_before);
    if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
    self.restorePending(before);
    const i = try b.read(index);
    // A fixed array's length is its type's, and nothing can resize it.
    const iteration_check = try walkGuard(Checker, b, prepared, owner, limit);
    var iteration_statements: std.ArrayList(typed.StatementId) = .empty;
    if (iteration_check) |guarded| try iteration_statements.append(self.allocator, guarded);
    const value = try iterationRead(Checker, self, b, owner, i, .{ .kind = kind, .fixed = fixed, .projection = if (projected) view else null });
    if (unpack) {
        const pair = try b.local(element);
        try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = pair, .value = value } }));
        const first_value = try b.node(first_type, .{ .field = .{ .base = try b.read(pair), .index = 0 } });
        const second_type = self.locals.items[@backingInt(second_slot)].ty;
        const second_value = try b.node(second_type, .{ .field = .{ .base = try b.read(pair), .index = 1 } });
        try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = first_slot, .value = first_value } }));
        try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = second_slot, .value = second_value } }));
    } else try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = first_slot, .value = value } }));
    try appendRebinding(Checker, self, b, &iteration_statements, position, i);
    try iteration_statements.append(self.allocator, body.id);
    const iteration = try b.stmt(.{ .block = try iteration_statements.toOwnedSlice(self.allocator) });
    const advance = try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } });
    const step = try b.stmt(.{ .block = if (iteration_check) |guarded|
        try self.allocator.dupe(typed.StatementId, &.{ guarded, advance })
    else
        try self.allocator.dupe(typed.StatementId, &.{advance}) });
    const setup = [_]typed.StatementId{
        try b.stmt(.{ .initialize = .{ .slot = owner, .value = iterable } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = limit, .value = if (fixed) |shape| try b.integer(@intCast(shape.length)) else try b.length(owner) } }),
        try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = iteration, .step = step } }),
    };
    // Walking the array in place, the loop reads the variable itself.
    return finishWalk(Checker, self, source_walk, prepared, &setup);
}

fn walkGuard(comptime Checker: type, b: collections.Builder(Checker), prepared: ?iteration_place.Source, owner: typed.LocalId, limit: typed.LocalId) Error!?typed.StatementId {
    return if (prepared) |place| try iteration_place.guard(Checker, b, place, owner, limit) else null;
}

fn walkSource(comptime Checker: type, b: collections.Builder(Checker), walk: Walk, input: typed.NodeId, owner: typed.LocalId, body: ast.StatementId) Error!?iteration_place.Source {
    return if (walk.in_place) null else try iteration_place.prepare(Checker, b, input, owner, .{ .statement = body });
}

/// Use D1's prepared entry, or the fixed-array copy decision, before the loop.
fn finishWalk(comptime Checker: type, self: *Checker, walk: Walk, prepared: ?iteration_place.Source, setup: []const typed.StatementId) Error!@FieldType(typed.Statement, "data") {
    if (prepared) |source_walk_place| {
        var statements: std.ArrayList(typed.StatementId) = .empty;
        try statements.appendSlice(self.allocator, source_walk_place.setup);
        try statements.appendSlice(self.allocator, setup[1..]);
        return .{ .block = try statements.toOwnedSlice(self.allocator) };
    }
    return .{ .block = try self.allocator.dupe(typed.StatementId, setup[@intFromBool(walk.in_place)..]) };
}
/// PY-FOR-REBIND-1: whether a loop body can assign `name`.
fn bodyAssigns(comptime Checker: type, self: *Checker, body: ast.StatementId, name: []const u8) Error!bool {
    return loop_rebinding.assigns(self.allocator, .{ .program = self.syntax, .src = self.src }, body, name);
}
/// The slot a `for` loop's position binds — only `enumerate` binds one —
/// and whether it is a variable of its own rather than the loop's counter.
const Position = struct { slot: typed.LocalId, rebound: bool };
/// PY-FOR-REBIND-1: an `enumerate` position the body never assigns is the
/// loop's counter itself, immutable and never negative
/// (`PY-ARRAY-NEGATIVE-1`); one the body assigns is a variable of its own,
/// copied from the counter at the top of every iteration.
fn loopPosition(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), each: ForEach, counter: typed.LocalId) Error!Position {
    if (!each.enumerated) return .{ .slot = counter, .rebound = false };
    if (try bodyAssigns(Checker, self, each.body, self.src.text(each.index_name.?))) return .{ .slot = try b.local(.i64), .rebound = true };
    self.locals.items[@backingInt(counter)].mutable = false;
    try self.counters.put(self.allocator, counter, {});
    return .{ .slot = counter, .rebound = false };
}
/// Copy the loop's counter into a position variable of its own at the top
/// of an iteration; a position that is the counter needs nothing.
fn appendRebinding(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), statements: *std.ArrayList(typed.StatementId), position: Position, counter: typed.NodeId) Error!void {
    if (position.rebound) try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = position.slot, .value = counter } }));
}
/// The source a `for` loop reads its elements from, decided around its body.
const Walk = struct { owner: ?typed.LocalId, variable: ?typed.LocalId, ty: typed.Type, in_place: bool = false };
/// Start deciding a loop's source. A managed collection is a reference, so
/// the loop's copy of it is only a pointer and is taken as before. A fixed
/// array held in a local variable waits for the body.
fn beginWalk(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), iterable: typed.NodeId, fixed: ?typed.Array) Error!Walk {
    const source_type = self.nodes.items[@backingInt(iterable)].ty;
    if (fixed == null) return .{ .owner = try b.local(source_type), .variable = null, .ty = source_type };
    const variable = switch (self.nodes.items[@backingInt(iterable)].data) {
        .local => |slot| slot,
        else => null,
    };
    return .{ .owner = null, .variable = variable, .ty = source_type };
}
/// Walk a fixed-array local directly unless the body replaces its root.
fn endWalk(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), walk: *Walk, body: ast.StatementId) Error!typed.LocalId {
    if (walk.owner) |owner| return owner;
    const syntax: loop_rebinding.Syntax = .{ .program = self.syntax, .src = self.src };
    if (walk.variable) |slot| if (!try loop_rebinding.rebinds(self.allocator, syntax, body, self.locals.items[@backingInt(slot)].name, false)) {
        walk.in_place = true;
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        return slot;
    };
    return b.local(walk.ty);
}
/// Read the element at `index` of the loop's source copy in `owner`.
fn iterationRead(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), owner: typed.LocalId, index: typed.NodeId, source_shape: IterationShape) Error!typed.NodeId {
    if (source_shape.fixed) |shape| return b.node(shape.element, .{ .index = .{ .base = try b.read(owner), .index = index } });
    return projectedIterationValue(Checker, self, b, owner, index, source_shape.kind, source_shape.projection);
}
/// Whether a type is a managed collection a loop can walk by position.
fn collectionType(comptime Checker: type, self: *Checker, candidate: typed.Type) bool {
    return candidate.isAggregate() and self.catalog.records[candidate.recordIndex()].isCollection();
}
/// The value one `for` iteration binds: a fixed array's element, a
/// dictionary view's projection, or the collection's own element kind.
fn iterationElement(comptime Checker: type, self: *Checker, iterable_type: typed.Type, fixed: ?typed.Array, projection: ?dictionary_views.Kind, span: source.Span) Error!typed.Type {
    if (fixed) |shape| return shape.element;
    if (projection) |view| return dictionary_views.element(&self.catalog, iterable_type, view, span);
    const schema = self.catalog.records[iterable_type.recordIndex()];
    return switch (schema.collection.kind) {
        .list => schema.shape.buffer.?,
        .string => iterable_type,
        .bytes => typed.Type.i64,
        .dictionary => schema.collection.key.?,
    };
}
/// `for x in reversed(xs):` and `for a, b in zip(xs, ys):` walk their sources
/// directly, so no intermediate list is materialised.
fn preludeIteration(comptime Checker: type, self: *Checker, stmt: ast.Statement, each: ForEach) Error!?[]const typed.StatementId {
    const node = self.syntax.nodes.items[@backingInt(each.iterable)];
    if (node.data != .call) return null;
    const call = node.data.call;
    if (!std.mem.eql(u8, self.src.text(call.name), "reversed") and !std.mem.eql(u8, self.src.text(call.name), "zip")) return null;
    if (!try self.preludeName(call)) return null;
    try call_arguments.positional(call, self.sink);
    const paired = std.mem.eql(u8, self.src.text(call.name), "zip");
    if (call.arguments.len != (if (paired) @as(usize, 2) else 1)) return self.sink.fail("E_ARITY", node.span, "reversed takes one iterable and zip takes two");
    if (paired != (each.index_name != null)) return self.sink.fail(eCollectionMethod, stmt.span, "zip binds two iteration names and reversed binds one");
    for (call.arguments) |id| try self.hintEmptyPreludeList(id, .i64);
    const sources = try self.allocator.alloc(typed.NodeId, call.arguments.len);
    for (call.arguments, sources) |id, *slot| slot.* = try self.expression(id);
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    const left_type = self.nodes.items[@backingInt(sources[0])].ty;
    const zip = if (paired) try builtins.reserveZip(stmt.span, left_type, self.nodes.items[@backingInt(sources[1])].ty) else null;
    const walk = if (zip) |pair| pair.left else try builtins.reserveWalk(stmt.span, left_type);
    const names = discardOnce(self.src, .{ each.index_name, each.name });
    const slots = [_]typed.LocalId{ walk.slot, if (zip) |pair| pair.right.slot else walk.slot };
    var hidden = [_]?typed.LocalId{ null, null };
    for (names, slots, &hidden) |maybe_name, slot, *earlier| if (maybe_name) |name| {
        if (try self.shadows(name)) return self.sink.fail(eShadowing, name, eIterationShadow);
        self.locals.items[@backingInt(slot)].mutable = false;
        self.locals.items[@backingInt(slot)].name = self.src.text(name);
        self.locals.items[@backingInt(slot)].declaration = name;
        // `reversed`/`zip` bind their names before the body checks, exactly like
        // the ordinary for-each path; function-scoped locals need the binding
        // marked initialized or a body read is refused as use-before-assignment.
        self.locals.items[@backingInt(slot)].ownership.initialized = true;
        self.locals.items[@backingInt(slot)].origin = .iteration;
        earlier.* = try self.bindScoped(self.src.text(name), slot);
    };
    defer for (names, hidden) |maybe_name, earlier| if (maybe_name) |name| self.unbindScoped(self.src.text(name), earlier);
    const before = try self.pendingState(self.locals.items.len);
    try self.loops.active.append(self.allocator, .{ .id = walk.loop, .before = before });
    defer _ = self.loops.active.pop();
    const init_before = try self.initSnapshot();
    const body = try self.statement(each.body);
    self.initRestore(init_before);
    if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
    self.restorePending(before);
    if (zip) |pair| {
        const statements = try builtins.zipStatements(.{ .span = stmt.span, .left = sources[0], .right = sources[1], .zip = pair, .body = body.id, .syntax_body = each.body });
        return statements;
    }
    const statements = try builtins.walkStatements(.{ .span = stmt.span, .input = sources[0], .walk = walk, .descending = true, .body = body.id, .syntax_body = each.body });
    return statements;
}
fn iterationValue(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), owner: typed.LocalId, kind: ManagedKind, index: typed.NodeId) Error!typed.NodeId {
    _ = self;
    const read = try b.operation(owner, if (kind == .dictionary) .key_at else .read, &.{index});
    return if (kind == .bytes) b.node(.i64, .{ .cast = read }) else read;
}
/// Read one iteration element, applying a dictionary view's projection when
/// the source is keys, values or items and using ordinary collection access otherwise.
fn projectedIterationValue(
    comptime Checker: type,
    self: *Checker,
    b: collections.Builder(Checker),
    owner: typed.LocalId,
    index: typed.NodeId,
    kind: ManagedKind,
    projection: ?dictionary_views.Kind,
) Error!typed.NodeId {
    if (projection) |view| return dictionary_views.at(Checker, self, b.span, owner, index, view);
    return iterationValue(Checker, self, b, owner, kind, index);
}
/// Whether a binding name is `_`, the discard name (`DISCARD-NAME-1`).
fn isDiscard(src: source.Source, name: source.Span) bool {
    return std.mem.eql(u8, src.text(name), "_");
}
/// The two iteration names of one loop with a second `_` dropped when the first
/// is `_` too: `for _, _ in ...` names nothing, so there is one discard to bind.
fn discardOnce(src: source.Source, names: [2]?source.Span) [2]?source.Span {
    const first = names[0] orelse return names;
    const second = names[1] orelse return names;
    return if (isDiscard(src, first) and isDiscard(src, second)) .{ first, null } else names;
}
fn statementForRange(comptime Checker: type, self: *Checker, stmt: ast.Statement, range: @FieldType(@FieldType(ast.Statement, "data"), "for_range")) Error!@FieldType(typed.Statement, "data") {
    try self.invalidateOptions(range.body);
    const loop_facts = try self.option_facts.snapshot(self.allocator);
    defer self.option_facts.restore(loop_facts);
    const name = self.src.text(range.name);
    if (try self.shadows(range.name)) return self.sink.fail(eShadowing, range.name, "iteration binding shadows an active declaration");
    const zero_start = self.syntax.nodes.items[@backingInt(range.start)].data == .unit;
    const start = if (zero_start) try (collections.Builder(Checker){ .checker = self, .span = range.name }).integer(0) else try self.expression(range.start);
    const end = try self.expression(range.end);
    const element = self.nodes.items[@backingInt(start)].ty;
    try self.requireInteger(element, range.name);
    try self.require(self.nodes.items[@backingInt(end)].ty, element, self.syntax.nodes.items[@backingInt(range.end)].span);
    const stepped = try self.rangeStep(range.name, range.step, element);
    // PY-FOR-REBIND-1: a body that assigns the name gets its own variable,
    // copied from a hidden counter at the top of every iteration, so the
    // assignment never changes which iteration comes next.
    const rebound = try bodyAssigns(Checker, self, range.body, name);
    const index: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .name = if (rebound) "<range-index>" else name,
        .declaration = range.name,
        .ty = element,
        .mutable = false,
        .ownership = .{ .initialized = true },
        .usage = .{ .reads = 1, .temporary = rebound },
    });
    // PY-ARRAY-NEGATIVE-1: an immutable induction variable counting up
    // from a non-negative start never holds a negative value.
    if (!rebound and stepped.ascending() and self.nonNegative(start, 0)) try self.counters.put(self.allocator, index, {});
    const limit: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{ .name = "<range-limit>", .declaration = range.name, .ty = element, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
    const variable: typed.LocalId = if (rebound) try reboundVariable(Checker, self, range.name, element) else index;
    const hidden = try self.bindScoped(name, variable);
    defer self.unbindScoped(name, hidden);
    const index_node: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .local = index } });
    const limit_node: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .local = limit } });
    const condition: typed.NodeId = if (stepped.lower) |lower| try lower.condition(index, limit) else @fromBackingInt(self.nodes.items.len);
    if (stepped.lower == null) try self.nodes.append(self.allocator, .{ .span = stmt.span, .ty = .bool, .data = .{ .binary = .{ .op = .lt, .left = index_node, .right = limit_node, .op_span = stmt.span } } });
    const one: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .integer = 1 } });
    const next: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .binary = .{ .op = .add, .left = index_node, .right = one, .op_span = range.name } } });
    const before = try self.pendingState(self.locals.items.len);
    const loop_id = self.loops.next;
    self.loops.next += 1;
    try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before });
    defer _ = self.loops.active.pop();
    const init_before = try self.initSnapshot();
    const body = try self.statement(range.body);
    self.initRestore(init_before);
    if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
    self.restorePending(before);
    const step: typed.StatementId = if (stepped.lower) |lower| try lower.advance(index, limit) else @fromBackingInt(self.statements.items.len);
    if (stepped.lower == null) try self.statements.append(self.allocator, .{ .span = range.name, .terminates = false, .data = .{ .assign = .{ .slot = index, .value = next } } });
    const setup = try stepped.setup();
    const iteration = if (rebound) try rebindFirst(Checker, self, range.name, variable, index_node, body.id) else body.id;
    return .{ .range_loop = .{
        .parts = try self.allocator.dupe(typed.RangeParts, &.{.{
            .binding = range.name,
            .start = .{ .slot = index, .value = start },
            .end = .{ .slot = limit, .value = end },
            .setup = setup,
            .loop = .{ .id = loop_id, .condition = condition, .body = iteration, .step = step },
        }}),
    } };
}
/// PY-FOR-REBIND-1: the visible loop variable of a counting loop whose body
/// assigns it: an ordinary mutable local, bound for the whole body.
fn reboundVariable(comptime Checker: type, self: *Checker, name: source.Span, element: typed.Type) Error!typed.LocalId {
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{ .name = self.src.text(name), .declaration = name, .ty = element, .mutable = false, .ownership = .{ .initialized = true }, .usage = .{ .reads = 1 }, .origin = .iteration });
    return slot;
}
/// One iteration of a counting loop whose body assigns its variable: the
/// variable takes the hidden counter's value, then the body runs.
fn rebindFirst(comptime Checker: type, self: *Checker, span: source.Span, variable: typed.LocalId, counter: typed.NodeId, body: typed.StatementId) Error!typed.StatementId {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const copy = try b.stmt(.{ .initialize = .{ .slot = variable, .value = counter } });
    return b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{ copy, body }) });
}
fn statementLoopExit(comptime Checker: type, self: *Checker, stmt: ast.Statement, continuing: bool, flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    if (self.loops.active.items.len == 0) return self.sink.fail("E_LOOP_EXIT", stmt.span, "break and continue require an enclosing loop");
    const loop = self.loops.active.items[self.loops.active.items.len - 1];
    try self.requireHandled(loop.before.len, stmt.span);
    try self.samePending(loop.before, stmt.span, eResultLoop);
    if (!continuing) self.loops.active.items[self.loops.active.items.len - 1].exited = true;
    flow.terminates = true;
    return .{ .loop_exit = .{ .target = loop.id, .continuing = continuing } };
}

/// The checker fields `reboundVariable` writes, so a test can rebind a loop variable alone.
const LocalStub = struct { allocator: std.mem.Allocator, src: source.Source, locals: std.ArrayList(typed.Local) = .empty };

test "each loop variable receives a fresh readonly local" {
    var stub: LocalStub = .{ .allocator = std.testing.allocator, .src = .{ .path = "loop.selka", .bytes = "for item in items", .line_starts = &.{} } };
    defer stub.locals.deinit(std.testing.allocator);
    const name: source.Span = .{ .start = 4, .end = 8 };
    const first = try reboundVariable(LocalStub, &stub, name, .i64);
    const second = try reboundVariable(LocalStub, &stub, name, .u8);
    try std.testing.expectEqual(@as(usize, 0), @backingInt(first));
    try std.testing.expectEqual(@as(usize, 1), @backingInt(second));
    try std.testing.expectEqualStrings("item", stub.locals.items[1].name);
    try std.testing.expect(!stub.locals.items[1].mutable);
    try std.testing.expectEqual(typed.Type.u8, stub.locals.items[1].ty);
}

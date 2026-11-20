//! Task groups in the checker (E1): `with parallel.group() as g:`, `g.submit(fn, ARGS)`,
//! `t.result()`, and the `E_TASK_*` rules of concurrency plan 2 §6.2. A group and its handles
//! are block-scoped locals. A `submit` checks `fn(ARGS)` as an ordinary direct call, so arity,
//! labels and argument markers get the direct call's own diagnostics. Lowering is the next lane's
//! work: this module only types the nodes that lowering will read (`typed.Node.task_*`).
const std = @import("std");
const ast = @import("ast.zig");
const own_parameters = @import("own_parameters.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const sema_shared = @import("sema_shared.zig");
const Error = diagnostic.Error;
const StatementFlow = sema_shared.StatementFlow;
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
const ScopeData = @FieldType(@FieldType(ast.Statement, "data"), "with_scope");

const eGroup = "E_TASK_GROUP";
const eEscape = "E_TASK_ESCAPE";
const eHandle = "E_TASK_HANDLE";
const eUnread = "E_TASK_RESULT_UNREAD";
const eMut = "E_TASK_MUT";
const eHost = "E_TASK_HOST";
const eResource = "E_TASK_RESOURCE";
const eCapability = "E_TASK_CAPABILITY";
const eLoan = "E_TASK_LOAN";

/// The message a handle takes when it is not the initialiser of a `const` binding.
const handle_message = "a task handle must initialise a `const` binding, as in `const t = g.submit(fn, ARGS)`";
/// The added hint a handle gets inside a loop: one task per item comes from `parallel.map`.
const loop_hint = "; inside a loop, `parallel.map(values, fn, ARGS)` runs one task per item and collects the results";

/// One handle a `const` binding holds: its local and the type `.result()` reads.
pub const Handle = struct { slot: typed.LocalId, result: typed.Type };

/// One managed value a submit lends (E1b): its local, the group, and the argument's span. Checked when the group's block
/// ends: the value must outlive the group's join.
pub const LentSubmit = struct { owner: typed.LocalId, group: typed.LocalId, span: source.Span };

/// The task-group state of one check, held by the checker.
pub const State = struct {
    /// Handles of `const` bindings whose blocks are still open.
    handles: std.ArrayList(Handle) = .empty,
    /// Managed values lent by submits of the groups whose blocks are still open (E1b).
    lent_submits: std.ArrayList(LentSubmit) = .empty,
    /// The `submit` call a `const` binding initialises, by span.
    const_site: ?source.Span = null,
    /// The `submit` call that is a bare statement, by span.
    bare_site: ?source.Span = null,
};

/// The two authorities a task argument must not hold: the Host capability, and an owned resource handle.
const Holds = enum { host, resource };

/// Whether a span is exactly another span.
fn sameSpan(a: source.Span, b: source.Span) bool {
    return a.start == b.start and a.end == b.end;
}

/// Whether a call names `parallel.<name>` with the standard module imported and no local called
/// `parallel`. The parser spells a module call either as an owner and a name, or as one dotted name.
pub fn isParallelCall(comptime Checker: type, self: *Checker, call: Call, name: []const u8) Error!bool {
    const spelled = self.src.text(call.name);
    const matches = if (call.owner) |owner|
        std.mem.eql(u8, self.src.text(owner), "parallel") and std.mem.eql(u8, spelled, name)
    else
        std.mem.startsWith(u8, spelled, "parallel.") and std.mem.eql(u8, spelled["parallel.".len..], name);
    if (!matches) return false;
    if (self.active.contains("parallel")) return false;
    const names = self.catalog.module_names orelse return false;
    return names.importsModule(call.owner orelse call.name, "parallel");
}

/// The trailing arguments of `parallel.map(values, fn, ARGS)` (E1c). A managed argument is lent to every item's call through a
/// lent box of its owner, so it is checked as a task argument: it may not hold the Host capability or an owned resource
/// handle, and a list element is bound first, as for a submit. The message names the argument, the call site.
pub fn checkMapArguments(comptime Checker: type, self: *Checker, call: Call) Error!void {
    if (call.arguments.len == 0) return;
    if (!try isParallelCall(Checker, self, call, "map")) return checkOtherMapNames(Checker, self, call);
    // No handle reaches a task (D-FFI-4): not in the values, not in the extra arguments. A task has no `Host`, so it
    // cannot get one from C either, and its results hold none but the null handle.
    for (call.arguments, 0..) |argument, position| {
        if (position == 1) continue;
        const value_id = self.resolved.at(@backingInt(argument)) orelse continue;
        const value = self.nodes.items[@backingInt(value_id)];
        if (@import("extern_types.zig").contains(value.ty, self.catalog.records)) return @import("extern_types.zig").refuse(self.sink, value.span, .task);
    }
    if (call.arguments.len <= 2) return refuseMapCapabilities(Checker, self, call);
    var visited: std.ArrayList(typed.Type) = .empty;
    defer visited.deinit(self.allocator);
    for (call.arguments[2..]) |argument| {
        const value_id = self.resolved.at(@backingInt(argument)) orelse continue;
        const value = self.nodes.items[@backingInt(value_id)];
        visited.clearRetainingCapacity();
        if (try holdsKind(self.allocator, self.catalog.records, value.ty, .host, &visited)) return self.sink.failOwnership(
            .{ .code = eHost, .rule = .K1 },
            value.span,
            "a parallel.map argument cannot be the Host capability or a value that holds it; Host authority stays with the calling thread",
        );
        visited.clearRetainingCapacity();
        if (try holdsKind(self.allocator, self.catalog.records, value.ty, .resource, &visited)) return self.sink.failOwnership(
            .{ .code = eResource, .rule = .K1 },
            value.span,
            "a parallel.map argument holds an owned resource handle such as an open file; read it before the map and pass the task the values",
        );
        if (readsListElement(Checker, self, argument) and managedArgument(Checker, self, argument)) return self.sink.failOwnership(
            .{ .code = eLoan, .rule = .K1 },
            self.syntax.nodes.items[@backingInt(argument)].span,
            "a list element cannot be passed to parallel.map directly; bind it first, as in `const item = xs[i]`, then pass `item`",
        );
    }
    try refuseMapCapabilities(Checker, self, call);
}

/// The map names other than `map` a program may call directly (`map_results`, `map_fallible`, `map_with1` to
/// `map_with5`): their items and trailing arguments reach the tasks as `map`'s do, so a capability among them is refused
/// the same way (W28). Their other argument rules are the ones each call already had.
fn checkOtherMapNames(comptime Checker: type, self: *Checker, call: Call) Error!void {
    const names = [_][]const u8{ "map_results", "map_fallible", "map_with1", "map_with2", "map_with3", "map_with4", "map_with5" };
    for (names) |name| if (try isParallelCall(Checker, self, call, name)) return refuseMapCapabilities(Checker, self, call);
}

/// Refuse a capability among a map's items (the first argument) or its trailing arguments (W28, D-W28-1). A trailing
/// argument fills the mapped function's parameter after the item, which the certain repair deletes when nothing reads it.
fn refuseMapCapabilities(comptime Checker: type, self: *Checker, call: Call) Error!void {
    const mapped = mappedFunction(Checker, self, call);
    for (call.arguments, 0..) |argument, position| {
        if (position == 1) continue;
        const value_id = self.resolved.at(@backingInt(argument)) orelse continue;
        const site: ?Site = if (position >= 2) if (mapped) |function| .{ .call = call, .position = position, .function = function, .parameter = position - 1 } else null else null;
        try refuseCapability(Checker, self, self.nodes.items[@backingInt(value_id)], if (position == 0) .map_items else .map_argument, site);
    }
}

/// The declaration of the function a map applies, when its second argument names one.
fn mappedFunction(comptime Checker: type, self: *Checker, call: Call) ?ast.Function {
    if (call.arguments.len < 2) return null;
    const value_id = self.resolved.at(@backingInt(call.arguments[1])) orelse return null;
    return switch (self.nodes.items[@backingInt(value_id)].data) {
        .function_value => |id| self.syntaxFunction(id),
        else => null,
    };
}

/// Whether a `with` scope's head opens a task group, `parallel.group()`.
pub fn opensGroup(comptime Checker: type, self: *Checker, head: ?ast.NodeId) Error!bool {
    const id = head orelse return false;
    const node = self.syntax.nodes.items[@backingInt(id)];
    if (node.data != .call) return false;
    return isParallelCall(Checker, self, node.data.call, "group");
}

/// `with parallel.group() as g:` (E1). The group is a block-scoped local, valid only inside the block;
/// its end joins the group's tasks, which lowering closes on every exit edge. A value a submit lends
/// stays loaned until the block ends. Handles are checked when their own block ends (`closeBlock`).
pub fn statementWithGroup(comptime Checker: type, self: *Checker, stmt: ast.Statement, scope: ScopeData, flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
    const head = self.syntax.nodes.items[@backingInt(scope.resource.?)];
    if (head.data.call.arguments.len != 0) return self.sink.failOwnership(.{ .code = eGroup, .rule = .K2 }, head.span, "`parallel.group()` takes no arguments; write `with parallel.group() as g:`");
    const declared = scope.name orelse return self.sink.failOwnership(.{ .code = eGroup, .rule = .K2 }, stmt.span, "a task group needs a name, as in `with parallel.group() as g:`");
    const name = self.src.text(declared);
    if (try self.shadows(declared)) return self.refuseShadowing(declared, "group name");
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .name = name,
        .declaration = declared,
        .ty = .task_group,
        .mutable = false,
        .ownership = .{ .initialized = true },
        .usage = .{ .reads = 1 },
    });
    const hidden = try self.bindScoped(name, slot);
    defer self.unbindScoped(name, hidden);
    const open: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = head.span, .ty = .task_group, .data = .task_group_open });
    const lent_mark = self.tasks.lent_submits.items.len;
    const body = try self.statement(scope.body);
    try checkLentOwners(Checker, self, slot, scope.body, lent_mark);
    try closeHandles(Checker, self, @backingInt(slot) + 1);
    flow.terminates = body.terminates;
    return .{ .with_scope = .{ .slot = slot, .resource = open, .body = body.id } };
}

/// Whether a call is `parallel.group()` or a method of a group or handle local (E1). Such a call
/// names no declaration, so the work queue queues its operands without resolving one.
pub fn taskCall(comptime Checker: type, self: *Checker, call: Call) Error!bool {
    if (try isParallelCall(Checker, self, call, "group")) return true;
    const owner = call.owner orelse return false;
    const slot = self.active.get(self.src.text(owner)) orelse return false;
    return switch (self.locals.items[@backingInt(slot)].ty) {
        .task_group, .task_handle => true,
        else => false,
    };
}

/// Refuse a group opened outside a `with` scope, and route a method call on a group or handle local
/// to its method. Returns null for every other call, which then takes the ordinary path.
pub fn checkCallSite(comptime Checker: type, self: *Checker, node: ast.Node, call: Call) Error!?typed.Node {
    if (try isParallelCall(Checker, self, call, "group")) return self.sink.failOwnership(.{ .code = eGroup, .rule = .K2 }, node.span, "`parallel.group()` opens a task group only as a `with` scope, as in `with parallel.group() as g:`");
    const owner = call.owner orelse return null;
    const slot = self.active.get(self.src.text(owner)) orelse return null;
    switch (self.locals.items[@backingInt(slot)].ty) {
        .task_group => {
            const value = try submit(Checker, self, node, call, slot);
            return value;
        },
        .task_handle => {
            const value = try readResult(Checker, self, node, call, slot);
            return value;
        },
        else => return null,
    }
}

/// `g.submit(fn, ARGS)`: the checked direct call `fn(ARGS)` becomes the task's work. The handle form
/// is a `const` initialiser, and the bare form is a statement that submits a procedure (`Unit`, no failure).
fn submit(comptime Checker: type, self: *Checker, node: ast.Node, call: Call, group: typed.LocalId) Error!typed.Node {
    if (!std.mem.eql(u8, self.src.text(call.name), "submit")) return self.sink.failOwnership(.{ .code = eGroup, .rule = .K2 }, call.name, "a task group has one method, `submit`: write `g.submit(fn, ARGS)`");
    if (call.arguments.len == 0) return self.sink.failOwnership(.{ .code = eGroup, .rule = .K2 }, call.name, "`submit` takes a function first, as in `g.submit(fn, ARGS)`");
    const fn_node = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    if (fn_node.data != .name or self.active.contains(self.src.text(fn_node.span))) return self.sink.failOwnership(
        .{ .code = eGroup, .rule = .K2 },
        fn_node.span,
        "`submit` takes a top-level function name first, as in `g.submit(fn, ARGS)`",
    );
    for (call.arguments[1..]) |argument| {
        const span = self.syntax.nodes.items[@backingInt(argument)].span;
        if (self.syntax.nodes.items[@backingInt(argument)].data == .mut_argument) return self.sink.failOwnership(
            .{ .code = eMut, .rule = .K1 },
            span,
            "a `mut` argument cannot go to a task: a task borrows its arguments read-only; " ++ "pass the value plainly, or give it with `own`",
        );
    }
    const names = if (call.argument_names.len == 0) call.argument_names else call.argument_names[1..];
    const direct: Call = .{ .name = fn_node.span, .arguments = call.arguments[1..], .argument_names = names };
    var direct_node = node;
    direct_node.data = .{ .call = direct };
    var checked: typed.Node = .{ .span = node.span, .ty = .unit, .data = .unit };
    try self.checkCall(direct_node, direct, &checked);
    if (checked.data != .call) return self.sink.failOwnership(.{ .code = eGroup, .rule = .K2 }, fn_node.span, "`submit` takes a function declared at top level");
    const arguments = checked.data.call.arguments;
    var visited: std.ArrayList(typed.Type) = .empty;
    defer visited.deinit(self.allocator);
    const task_function = self.syntaxFunction(checked.data.call.function);
    for (arguments, 0..) |argument, index| {
        const value = self.nodes.items[@backingInt(argument)];
        if (@import("extern_types.zig").contains(value.ty, self.catalog.records)) return @import("extern_types.zig").refuse(self.sink, value.span, .task);
        visited.clearRetainingCapacity();
        if (try holdsKind(self.allocator, self.catalog.records, value.ty, .host, &visited)) return self.sink.failOwnership(
            .{ .code = eHost, .rule = .K1 },
            value.span,
            "a task cannot take the Host capability or a value that holds it; " ++ "Host authority stays with the calling thread",
        );
        visited.clearRetainingCapacity();
        if (try holdsKind(self.allocator, self.catalog.records, value.ty, .resource, &visited)) return self.sink.failOwnership(
            .{ .code = eResource, .rule = .K1 },
            value.span,
            "a task argument holds an owned resource handle such as an open file; " ++ "read it before the group and pass the task the values",
        );
        const site: ?Site = if (index + 1 < call.arguments.len) .{ .call = call, .position = index + 1, .function = task_function, .parameter = index } else null;
        try refuseCapability(Checker, self, value, .submit_argument, site);
    }
    for (call.arguments[1..]) |argument| {
        if (self.syntax.nodes.items[@backingInt(argument)].data == .own_argument) continue;
        const owner = lentOwner(self, argument) orelse continue;
        if (readsListElement(Checker, self, argument) and managedArgument(Checker, self, argument)) return self.sink.failOwnership(
            .{ .code = eLoan, .rule = .K1 },
            self.syntax.nodes.items[@backingInt(argument)].span,
            "a list element cannot be lent to a task directly; bind it first, as in `const item = xs[i]`, then pass `item`",
        );
        if (own_parameters.managed(self.catalog.records, self.locals.items[@backingInt(owner)].ty)) {
            try self.tasks.lent_submits.append(self.allocator, .{ .owner = owner, .group = group, .span = self.syntax.nodes.items[@backingInt(argument)].span });
        }
    }
    const call_id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    // This hidden call is the callable use, while the task node retains the
    // complete submit span. V4's wrapper repair must replace only this name.
    checked.span = fn_node.span;
    try self.nodes.append(self.allocator, checked);
    if (self.tasks.bare_site) |site| if (sameSpan(site, node.span)) {
        if (checked.ty != .unit or typed.resultShape(checked.ty, self.catalog.records) != null) return self.sink.failOwnership(
            .{ .code = eUnread, .rule = .K2 },
            node.span,
            "a bare `submit` runs only a procedure that returns nothing and cannot fail; " ++ "bind the handle with `const t = g.submit(fn, ARGS)` and read `t.result()`",
        );
        return .{ .span = node.span, .ty = .unit, .data = .{ .task_submit = .{ .group = group, .call = call_id } } };
    };
    if (self.tasks.const_site) |site| if (sameSpan(site, node.span)) {
        return .{ .span = node.span, .ty = .task_handle, .data = .{ .task_submit = .{ .group = group, .call = call_id } } };
    };
    if (self.loops.active.items.len > 0) return self.sink.failOwnership(.{ .code = eHandle, .rule = .K2 }, node.span, handle_message ++ loop_hint);
    return self.sink.failOwnership(.{ .code = eHandle, .rule = .K2 }, node.span, handle_message);
}

/// `t.result()` (E1): the value of the submitted task, joined here. Reading it counts as the read the
/// block's end requires, and the node takes the handle's value type, which is the checked result of a
/// fallible `fn`.
fn readResult(comptime Checker: type, self: *Checker, node: ast.Node, call: Call, slot: typed.LocalId) Error!typed.Node {
    if (!std.mem.eql(u8, self.src.text(call.name), "result")) return self.sink.failOwnership(.{ .code = eHandle, .rule = .K2 }, call.name, "a task handle has one method, `result`: write `t.result()`");
    if (call.arguments.len != 0) return self.sink.failOwnership(.{ .code = eHandle, .rule = .K2 }, call.name, "`result()` takes no arguments");
    const handle = for (self.tasks.handles.items) |held| {
        if (held.slot == slot) break held;
    } else return self.sink.failOwnership(.{ .code = eHandle, .rule = .K2 }, node.span, "a task handle is read only inside the group block that submitted it");
    // A task's value is taken out of the handle by its first read, so a second read has nothing to take (E1b).
    if (self.locals.items[@backingInt(slot)].usage.reads > 0) return self.sink.failOwnership(.{ .code = eHandle, .rule = .K2 }, node.span, "a task's result can be read once; bind it to a `const` and read that");
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    return .{ .span = node.span, .ty = handle.result, .data = .{ .task_result = slot } };
}

/// The end of a group's block (E1b): every managed value its submits lend must outlive the group's join. A value declared
/// before the `with`, or at the top level of the block, is dropped after the join, because the join reads it (own.zig, rule A).
/// A value declared in a nested block (a loop, a branch, an inner block) is dropped when that block ends, which can be
/// before the task reads it, so the group refuses it. The entries of the block's submits are removed either way.
fn checkLentOwners(comptime Checker: type, self: *Checker, group: typed.LocalId, body: ast.StatementId, mark: usize) Error!void {
    defer self.tasks.lent_submits.shrinkRetainingCapacity(mark);
    for (self.tasks.lent_submits.items[mark..]) |lent| {
        if (@backingInt(lent.owner) < @backingInt(group)) continue;
        if (declaredAtTop(Checker, self, body, lent.owner)) continue;
        return self.sink.failOwnership(.{ .code = eLoan, .rule = .K1 }, lent.span, "a value lent to a task must outlive its group: declare it before the `with` or at the top level of its block, or pass it `own`");
    }
}

/// Whether `owner` is declared by a statement at the top level of the block `body`. The declaration is matched by its
/// name, so a deferred `const` (assigned in each branch) counts as declared where its binding stands, not where it is
/// first assigned.
fn declaredAtTop(comptime Checker: type, self: *Checker, body: ast.StatementId, owner: typed.LocalId) bool {
    const declared = self.locals.items[@backingInt(owner)].declaration;
    const items = switch (self.syntax.statements.items[@backingInt(body)].data) {
        .block => |block| block,
        else => return false,
    };
    for (items) |item| switch (self.syntax.statements.items[@backingInt(item)].data) {
        .binding => |binding| if (sameSpan(binding.name, declared)) return true,
        else => {},
    };
    return false;
}

/// Refuse a borrowed value given to a task as a direct argument (E1b). A borrowing call result (R2-R4) or a borrowed
/// selection names an owner the group cannot lend, and the task's environment would free what its owner still holds. The
/// refusal reads the callee's declared `from` contract; the repair is `copy(...)`,
/// which gives the task its own value. Returns true when any argument is refused.
pub fn refuseBorrowedArguments(allocator: std.mem.Allocator, nodes: []const typed.Node, functions: []const typed.Function, records: []const typed.Record, sink: *diagnostic.Sink) diagnostic.Error!bool {
    var refused = false;
    for (nodes) |node| {
        if (node.data != .task_submit) continue;
        const call = nodes[@backingInt(node.data.task_submit.call)];
        for (call.data.call.arguments) |argument| {
            const value = nodes[@backingInt(argument)];
            const borrowed = switch (value.data) {
                .borrow_selection => true,
                .call => |callee| @import("view_function_value.zig").borrowsResult(records, functions[@backingInt(callee.function)]),
                // A dictionary lookup with a fallback answers a managed value by reference (`dicts.get`).
                .buffer_operation => |operation| operation.kind == .get and own_parameters.managed(records, value.ty),
                else => false,
            };
            if (!borrowed) continue;
            try sink.items.append(allocator, diagnostic.ownership(.{ .code = eLoan, .rule = .K1 }, value.span, "a borrowed value cannot be given to a task directly; write copy(...) around it to give the task its own value"));
            refused = true;
        }
    }
    return refused;
}

/// Record the handle a `const` binding took (E1), so its `.result()` reads know the value type.
pub fn recordHandle(comptime Checker: type, self: *Checker, slot: typed.LocalId, value: typed.NodeId) Error!void {
    const submitted = switch (self.nodes.items[@backingInt(value)].data) {
        .task_submit => |submit_node| submit_node,
        else => return error.InternalError,
    };
    const result = self.nodes.items[@backingInt(submitted.call)].ty;
    try self.tasks.handles.append(self.allocator, .{ .slot = slot, .result = result });
}

/// A block is ending (E1): every handle its own `const` bindings took must have been read with
/// `.result()`, and the handles leave scope with their block.
pub fn closeBlock(comptime Checker: type, self: *Checker, first_local: usize) Error!void {
    try closeHandles(Checker, self, first_local);
}

/// Check the handles declared at or after `first_local` and drop them from the open set.
fn closeHandles(comptime Checker: type, self: *Checker, first_local: usize) Error!void {
    var kept: usize = 0;
    for (self.tasks.handles.items) |held| {
        if (@backingInt(held.slot) < first_local) {
            self.tasks.handles.items[kept] = held;
            kept += 1;
            continue;
        }
        const local = self.locals.items[@backingInt(held.slot)];
        if (local.usage.reads == 0) {
            const message = try std.fmt.allocPrint(self.allocator, "task handle `{s}` is never read; read it with `{s}.result()` before its group block ends", .{ self.src.text(local.declaration), self.src.text(local.declaration) });
            return self.sink.failOwnership(.{ .code = eUnread, .rule = .K2 }, local.declaration, message);
        }
    }
    self.tasks.handles.shrinkRetainingCapacity(kept);
}

/// A group or handle named as a value (E1): it cannot be stored, passed, returned or captured.
pub fn refuseEscape(comptime Checker: type, self: *Checker, slot: typed.LocalId, name: source.Span) Error!void {
    switch (self.locals.items[@backingInt(slot)].ty) {
        .task_group => return self.sink.failOwnership(.{ .code = eEscape, .rule = .K2 }, name, "a task group cannot be stored, passed or returned; use it only as `g.submit(fn, ARGS)` inside its `with` block"),
        .task_handle => return self.sink.failOwnership(.{ .code = eEscape, .rule = .K2 }, name, "a task handle cannot be stored, passed or returned; read it with `t.result()` inside its group block"),
        else => {},
    }
}

/// Whether a lent argument's path reads an element of a list (E1b). The ownership pass cannot yet lend a list element
/// directly, so such an element is lent through a binding; a dictionary value and a scalar are not refused.
fn readsListElement(comptime Checker: type, self: *Checker, argument: ast.NodeId) bool {
    var current = argument;
    while (true) {
        const node = self.syntax.nodes.items[@backingInt(current)];
        switch (node.data) {
            .index => |index| {
                if (isListBase(Checker, self, index.base)) return true;
                current = index.base;
            },
            .field => |field| current = field.base,
            else => return false,
        }
    }
}

/// Whether the base of an element read is a list: a local name of list type, or a field or element of one (unknown bases count as lists).
fn isListBase(comptime Checker: type, self: *Checker, base: ast.NodeId) bool {
    const node = self.syntax.nodes.items[@backingInt(base)];
    const ty = switch (node.data) {
        .name => |name| if (self.active.get(self.src.text(name))) |slot| self.locals.items[@backingInt(slot)].ty else return true,
        else => blk: {
            const value = self.resolved.at(@backingInt(base)) orelse return true;
            break :blk self.nodes.items[@backingInt(value)].ty;
        },
    };
    if (!ty.isAggregate()) return false;
    const record = self.catalog.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .list;
}

/// Whether a lent argument's value is a managed value (a list, string, record and so on), by its checked type.
fn managedArgument(comptime Checker: type, self: *Checker, argument: ast.NodeId) bool {
    const value = self.resolved.at(@backingInt(argument)) orelse return true;
    return own_parameters.managed(self.catalog.records, self.nodes.items[@backingInt(value)].ty);
}

/// The local a lent argument reads from: the name itself, or the root of a field or element path.
fn lentOwner(self: anytype, argument: ast.NodeId) ?typed.LocalId {
    var current = argument;
    while (true) {
        const node = self.syntax.nodes.items[@backingInt(current)];
        switch (node.data) {
            .name => |name| return self.active.get(self.src.text(name)),
            .field => |field| current = field.base,
            .index => |index| current = index.base,
            else => return null,
        }
    }
}

/// Where a value reaches a task, for the wording of `E_TASK_CAPABILITY`.
const Reach = enum { submit_argument, map_argument, map_items };

/// One step of the path from a task argument's type to the capability it holds.
const Step = union(enum) { field: []const u8, element, option, case: []const u8 };

/// Refuse a task argument that is, or can hold, a capability other than `Host` (W28, D-W28-1): a task's call to it would
/// wait for, or interleave with, every other task's calls to the same provider. The message names the argument, its type,
/// the field or element that holds the capability, and what to write instead.
fn refuseCapability(comptime Checker: type, self: *Checker, value: typed.Node, reach: Reach, site: ?Site) Error!void {
    var visited: std.ArrayList(typed.Type) = .empty;
    defer visited.deinit(self.allocator);
    var steps: std.ArrayList(Step) = .empty;
    defer steps.deinit(self.allocator);
    const held = try findCapability(self.allocator, self.catalog.records, value.ty, &visited, &steps) orelse return;
    var text: std.Io.Writer.Allocating = .init(self.allocator);
    defer text.deinit();
    const surface = try typed.surfaceTypeName(self.allocator, value.ty, self.catalog.records);
    defer self.allocator.free(surface);
    const type_name = try typed.sourceTypeSpelling(self.allocator, surface);
    defer self.allocator.free(type_name);
    writeCapabilityMessage(&text.writer, .{ .spelled = self.src.text(value.span), .type_name = type_name, .held = held, .steps = steps.items, .reach = reach }) catch return error.OutOfMemory;
    const message = try text.toOwnedSlice();
    var item = diagnostic.ownership(.{ .code = eCapability, .rule = .K1 }, value.span, message);
    if (site) |known| item.provenance.fix = try unusedArgumentFix(Checker, self, known);
    try self.sink.items.append(self.allocator, item);
    return error.SourceError;
}

/// A refused argument's call and the task function's parameter it fills, for the one certain repair.
const Site = struct { call: Call, position: usize, function: ast.Function, parameter: usize };

/// The certain repair of `E_TASK_CAPABILITY` (W28): when the task function never reads the parameter the refused argument
/// fills, delete the argument and the parameter. It is certain only when nothing else can see the change: the parameter
/// is a plain one whose name occurs once in its module's file (its declaration: a capability parameter that is never read
/// must start with `_`, `E_UNUSED_CAPABILITY`), the function is not public and its name occurs exactly twice in that file
/// (its declaration and this task call), and the call names no argument. Any other shape gets no fix.
fn unusedArgumentFix(comptime Checker: type, self: *Checker, site: Site) Error!?diagnostic.Fix {
    const parameters = site.function.signature.parameters;
    if (site.parameter >= parameters.len) return null;
    const parameter = parameters[site.parameter];
    if (parameter.mut or parameter.own or parameter.named or parameter.default_value != null) return null;
    for (site.call.argument_names) |name| if (name != null) return null;
    const argument = self.syntax.nodes.items[@backingInt(site.call.arguments[site.position])];
    if (argument.data != .name) return null;
    if (ast.isPublicDeclaration(self.syntax, site.function.name)) return null;
    const file = fileRange(self.src, site.function.name) orelse return null;
    const call_file = fileRange(self.src, argument.span) orelse return null;
    if (file.start != call_file.start) return null;
    const bytes = self.src.bytes[file.start..file.end];
    if (occurrences(bytes, self.src.text(parameter.name)) != 1) return null;
    if (occurrences(bytes, self.src.text(site.function.name)) != 2) return null;
    const arguments = site.call.arguments;
    const argument_edit = listItemEdit(nodeSpans(self, arguments, site.position));
    const parameter_spans: [3]?source.Span = .{
        if (site.parameter > 0) parameterSpan(parameters[site.parameter - 1]) else null,
        parameterSpan(parameter),
        if (site.parameter + 1 < parameters.len) parameterSpan(parameters[site.parameter + 1]) else null,
    };
    const parameter_edit = listItemEdit(parameter_spans);
    const more = try self.allocator.alloc(diagnostic.Edit, 1);
    more[0] = parameter_edit;
    return .{ .edit = argument_edit, .more = more };
}

/// The spans of a call's arguments before, at and after `position`.
fn nodeSpans(self: anytype, arguments: []const ast.NodeId, position: usize) [3]?source.Span {
    return .{
        if (position > 0) self.syntax.nodes.items[@backingInt(arguments[position - 1])].span else null,
        self.syntax.nodes.items[@backingInt(arguments[position])].span,
        if (position + 1 < arguments.len) self.syntax.nodes.items[@backingInt(arguments[position + 1])].span else null,
    };
}

/// A plain parameter's text, from its name to the end of its type.
fn parameterSpan(parameter: ast.Parameter) source.Span {
    return .{ .start = parameter.name.start, .end = parameter.ty.end };
}

/// The edit deleting the middle of three neighbouring list items and one separating comma: up to the next item's start
/// when one follows, else from the end of the item before it.
fn listItemEdit(spans: [3]?source.Span) diagnostic.Edit {
    const item = spans[1].?;
    if (spans[2]) |next| return .{ .span = .{ .start = item.start, .end = next.start }, .text = "" };
    if (spans[0]) |previous| return .{ .span = .{ .start = previous.end, .end = item.end }, .text = "" };
    return .{ .span = item, .text = "" };
}

/// The byte range of the file that holds `span`: the whole source, or the module of a merged project source.
fn fileRange(src: source.Source, span: source.Span) ?source.Span {
    if (src.origins.len == 0) return .{ .start = 0, .end = src.bytes.len };
    const found = src.originalSpan(span) catch return null;
    const origin = src.origins[found.input];
    return .{ .start = origin.start, .end = origin.start + origin.original.bytes.len };
}

/// How many times `name` occurs in `bytes` as a whole identifier, in code, comments and text alike.
fn occurrences(bytes: []const u8, name: []const u8) usize {
    if (name.len == 0) return 0;
    var count: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, at, name)) |found| {
        const end = found + name.len;
        const before = found > 0 and identifierByte(bytes[found - 1]);
        const after = end < bytes.len and identifierByte(bytes[end]);
        if (!before and !after) count += 1;
        at = end;
    }
    return count;
}

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// What `E_TASK_CAPABILITY`'s message names: the argument as spelled, its type, the capability and the path to it.
const Refused = struct { spelled: []const u8, type_name: []const u8, held: typed.Type, steps: []const Step, reach: Reach };

/// Write `E_TASK_CAPABILITY`'s message: the argument, its type, the field or element that holds the capability, why a task
/// cannot take it, and what to write instead.
fn writeCapabilityMessage(writer: *std.Io.Writer, refused: Refused) std.Io.Writer.Error!void {
    const spelled = if (std.mem.startsWith(u8, refused.spelled, "own ")) refused.spelled["own ".len..] else refused.spelled;
    const named = spelled.len > 0 and spelled.len <= 40 and std.mem.indexOfScalar(u8, spelled, '\n') == null;
    const capability = capabilityName(refused.held);
    const items = refused.reach == .map_items;
    if (items) {
        if (named) try writer.print("the items of `{s}`", .{spelled}) else try writer.writeAll("the items of this list");
    } else if (named) try writer.print("`{s}`", .{spelled}) else try writer.writeAll("this argument");
    const path = refused.steps[@min(@intFromBool(items), refused.steps.len)..];
    if (path.len == 0) {
        try writer.print(" {s} {s} `{s}`", .{ if (items) "are each" else "is", article(capability), capability });
    } else {
        if (!items) try writer.print(" (a `{s}`)", .{refused.type_name});
        try writer.print(" {s} {s} `{s}` (", .{ if (items) "each hold" else "holds", article(capability), capability });
        for (path, 0..) |step, index| {
            if (index > 0) try writer.writeAll(", then ");
            switch (step) {
                .field => |name| try writer.print("field `{s}`", .{name}),
                .element => try writer.writeAll("an element"),
                .option => try writer.writeAll("its value"),
                .case => |name| try writer.print("case `{s}`", .{name}),
            }
        }
        try writer.writeAll(")");
    }
    try writer.print(", a capability that reads or writes the outside world, and {s} cannot take it: ", .{switch (refused.reach) {
        .submit_argument => "a task",
        .map_argument, .map_items => "a parallel.map task",
    }});
    try writer.writeAll(if (refused.held == .stop_cap)
        "a task is a computation the program joins, not a loop that waits, and it takes values only. "
    else
        "its calls would wait for, or interleave with, every other task's calls to the same provider. ");
    try writer.writeAll(switch (refused.held) {
        .stream_cap => "Let the task return what it would print, and print it after the group or map " ++
            "(docs/concurrency.md#tasks-take-values)",
        .stop_cap => "Ask process.stop_requested(stop) before each group or map and start no more work once it is True, or " ++
            "pass the task its answer as a bool (docs/io.md#hearing-a-stop)",
        .network_cap => "Make the network calls before or after the tasks and pass the task the bytes; a service and its " ++
            "client in one program are one event loop that accepts and dials " ++
            "(`network.dial`, docs/standard-library.md#dialling-from-the-event-loop)",
        else => "Do the reading or writing before or after the tasks, pass the task the values, and let it return its result " ++
            "(docs/concurrency.md#tasks-take-values)",
    });
}

/// The indefinite article before a capability's name.
fn article(name: []const u8) []const u8 {
    return if (name.len > 0 and std.mem.indexOfScalar(u8, "AEIOU", name[0]) != null) "an" else "a";
}

/// The source spelling of a capability type, as the guides write it (`Entropy`, not the older `Random`).
fn capabilityName(ty: typed.Type) []const u8 {
    if (ty == .stream_cap) return "Stream";
    return @import("prelude.zig").reservedTypeName(ty) orelse "capability";
}

/// The first capability other than `Host` that a value of type `ty` can hold, with the path to it in `steps` (fields,
/// elements and case payloads, outermost first). `visited` guards recursive types. `Host` has its own refusal.
fn findCapability(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, visited: *std.ArrayList(typed.Type), steps: *std.ArrayList(Step)) Error!?typed.Type {
    if (ty.capabilityIndex() != null) return if (ty == .host_cap) null else ty;
    if (!ty.isAggregate()) return null;
    for (visited.items) |seen| if (seen == ty) return null;
    try visited.append(allocator, ty);
    const record = records[ty.recordIndex()];
    for (record.fields) |field| {
        try steps.append(allocator, .{ .field = field.name });
        if (try findCapability(allocator, records, field.ty, visited, steps)) |found| return found;
        _ = steps.pop();
    }
    const elements = [_]?typed.Type{
        record.shape.buffer,
        if (record.shape.array) |array| array.element else null,
        record.shape.domain,
    };
    for (elements) |maybe| {
        const element = maybe orelse continue;
        try steps.append(allocator, .element);
        if (try findCapability(allocator, records, element, visited, steps)) |found| return found;
        _ = steps.pop();
    }
    const option = std.mem.startsWith(u8, record.name, "Option<") or std.mem.startsWith(u8, record.name, "std_result::Option<");
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        const payload = case.payload orelse continue;
        try steps.append(allocator, if (option) .option else .{ .case = case.name });
        if (try findCapability(allocator, records, payload, visited, steps)) |found| return found;
        _ = steps.pop();
    };
    return null;
}

/// Whether a value of type `ty` can hold the authority or resource named by `which`, walking record
/// fields, element types and variant payloads. `visited` guards recursive types.
fn holdsKind(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, which: Holds, visited: *std.ArrayList(typed.Type)) Error!bool {
    switch (which) {
        .host => if (ty == .host_cap) return true,
        .resource => if (ty.isFile()) return true,
    }
    if (!ty.isAggregate()) return false;
    for (visited.items) |seen| if (seen == ty) return false;
    try visited.append(allocator, ty);
    const record = records[ty.recordIndex()];
    if (which == .resource and record.shape.resource != null) return true;
    for (record.fields) |field| if (try holdsKind(allocator, records, field.ty, which, visited)) return true;
    if (record.shape.buffer) |element| if (try holdsKind(allocator, records, element, which, visited)) return true;
    if (record.shape.array) |array| if (try holdsKind(allocator, records, array.element, which, visited)) return true;
    if (record.shape.domain) |backing| if (try holdsKind(allocator, records, backing, which, visited)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        const payload = case.payload orelse continue;
        if (try holdsKind(allocator, records, payload, which, visited)) return true;
    };
    return false;
}

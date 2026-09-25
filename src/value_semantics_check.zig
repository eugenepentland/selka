//! Checker rules that only value semantics has (`VALUE-SEMANTICS-4`,
//! `VALUE-SEMANTICS-6`): a write that could only change a copy nobody reads
//! again is an error instead of a silent loss.
//!
//! - A `for` variable (with `enumerate`, `zip`, `reversed`, `d.values()` and
//!   `d.items()`) and a named `match` payload binding of a value another name
//!   holds are copies of the element or payload. Writing through one
//!   (`row.append(0)`, `p.x = 1`, `row[0] = 5`, passing `mut row`) is
//!   `E_VALUE_BINDING_WRITE`. A binding of a `class` or Cell is a shared
//!   reference and stays writable; a match on a call result binds the result
//!   itself, which nothing else holds.
//! - Writing into a function's returned value (`f(x).items.append(1)`) changes
//!   a temporary copy no name holds: `E_VALUE_TEMPORARY_WRITE`.
//! - A `mut` parameter the body never writes because the only change went to a
//!   local copy of it gets a hint to store the copy back, not to drop `mut`.
const std = @import("std");
const typed = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const diagnostic = @import("diagnostic.zig");
const mutation = @import("mutation.zig");
const source = @import("source.zig");
const values = @import("value_semantics.zig");

/// Allocation failure while collecting a function's writes.
pub const Error = std.mem.Allocator.Error;

/// Error code for a write through a `for` variable or `match` binding, which
/// holds a copy, so the write would be lost.
pub const binding_write_code = "E_VALUE_BINDING_WRITE";
/// Error code for a write into a function's returned value: a temporary copy
/// no name holds.
pub const temporary_write_code = "E_VALUE_TEMPORARY_WRITE";

const temporary_write_text = "this changes a value a function returned, which is a temporary copy that no name holds, so the change is lost; " ++
    "assign the result to a local, change the local, and store it back where it belongs (or change that place through a `mut` parameter)";
const loop_write_text = "`{s}` holds a copy of the element this loop visits, so a change to it is lost when the iteration ends; " ++
    "change the collection through its place (`for i in range(len(xs)): xs[i]...`, `d[key]...`), " ++
    "or assign `{s}` to a local first if the change is meant to stay local";
const payload_write_text = "`{s}` holds a copy of the matched payload, so a change to it does not reach the matched value; " ++
    "change the value through its place, or assign `{s}` to a local first if the change is meant to stay local";

/// Report every write through a value binding or into a returned value in
/// function `index`. Returns whether any diagnostic was reported.
pub fn checkWrites(allocator: std.mem.Allocator, program: typed.Program, index: usize, sink: *diagnostic.Sink) Error!bool {
    const function = program.functions[index];
    if (function.policy.host != null) return false;
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const facts = try values.Facts.collect(a, program, function);
    const bindings = try bindingLocals(a, &facts);
    var reported = false;
    var walker = try typed_walk.Walker.init(a, program, function.scope.body);
    while (try walker.next()) |item| {
        const site = writeAt(&facts, item) orelse continue;
        if (bindingRoot(&facts, site.root, bindings)) |root| {
            try sink.items.append(allocator, .{ .code = binding_write_code, .span = site.span, .message = try bindingMessage(allocator, function, root, bindings[@backingInt(root)]) });
            reported = true;
        } else if (temporaryRoot(&facts, site.root)) {
            try sink.items.append(allocator, .{ .code = temporary_write_code, .span = site.span, .message = temporary_write_text });
            reported = true;
        }
    }
    return reported;
}

/// One named local a `mut` parameter's only change went to, and the value
/// (a path into the parameter) it copied.
pub const LostCopy = struct { local: typed.LocalId, value: typed.NodeId };

/// VALUE-SEMANTICS-6: when parameter `position` of `function` is declared
/// `mut` but never written, the named local that holds a copy of the
/// parameter (or of a path into it) and is itself written, if there is one.
pub fn lostCopy(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function, position: usize) Error!?LostCopy {
    if (function.policy.host != null) return null;
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const facts = try values.Facts.collect(a, program, function);
    const copies = try a.alloc(?typed.NodeId, function.scope.locals.len);
    @memset(copies, null);
    var stores = try typed_walk.Walker.init(a, program, function.scope.body);
    while (try stores.next()) |item| switch (item) {
        .expression => {},
        .statement => |id| switch (program.statements[@backingInt(id)].data) {
            .initialize, .assign => |store| {
                const slot = @backingInt(store.slot);
                if (slot < function.signature.parameter_count or !facts.namedStore(store.slot)) continue;
                const root = values.pathRoot(program, store.value) orelse continue;
                if (@backingInt(root) == position) copies[slot] = store.value;
            },
            else => {},
        },
    };
    var writes = try typed_walk.Walker.init(a, program, function.scope.body);
    while (try writes.next()) |item| {
        const site = writeAt(&facts, item) orelse continue;
        const local = values.namedRoot(&facts, site.root) orelse continue;
        const value = copies[@backingInt(local)] orelse continue;
        return .{ .local = local, .value = value };
    }
    return null;
}

/// What kind of value binding a local is, if any.
const Binding = enum { none, loop, payload };

/// One located write and the local it is rooted at.
const WriteSite = struct { root: typed.LocalId, span: source.Span };

fn writeAt(facts: *const values.Facts, item: typed_walk.Item) ?WriteSite {
    return switch (item) {
        .expression => |id| expressionWrite(facts.program, facts.function, id),
        .statement => |id| statementWrite(facts, id),
    };
}

fn bindingLocals(allocator: std.mem.Allocator, facts: *const values.Facts) Error![]Binding {
    const program = facts.program;
    const function = facts.function;
    const kinds = try allocator.alloc(Binding, function.scope.locals.len);
    for (function.scope.locals, kinds, 0..) |local, *kind, slot| {
        // A `class` or Cell binding is a shared reference, never a copy.
        const shared = values.sharedRecord(program.records, local.ty);
        kind.* = if (slot >= function.signature.parameter_count and local.origin == .iteration and !shared) .loop else .none;
    }
    var walker = try typed_walk.Walker.init(allocator, program, function.scope.body);
    while (try walker.next()) |item| switch (item) {
        .expression => {},
        .statement => |id| switch (program.statements[@backingInt(id)].data) {
            // Matching a temporary (a call result) binds the value itself;
            // only a payload of a value that has another home is a copy.
            .match => |match| if (facts.classify(match.value, null) != .fresh) for (match.arms) |arm| if (arm.slot) |slot| {
                kinds[@backingInt(slot)] = .payload;
            },
            else => {},
        },
    };
    // A named-field pattern binds each name to a field of the hidden payload
    // slot; those names are payload bindings too.
    var fields = try typed_walk.Walker.init(allocator, program, function.scope.body);
    while (try fields.next()) |item| {
        const id = switch (item) {
            .statement => |statement| statement,
            .expression => continue,
        };
        const store = switch (program.statements[@backingInt(id)].data) {
            .initialize => |store| store,
            else => continue,
        };
        const base = payloadFieldBase(program, store.value) orelse continue;
        if (kinds[@backingInt(base)] == .payload and !values.namedHome(function, @backingInt(base)) and values.namedHome(function, @backingInt(store.slot))) kinds[@backingInt(store.slot)] = .payload;
    }
    // Only a binding the source names holds a copy the reader can write.
    for (kinds, function.scope.locals, 0..) |*kind, local, slot| {
        if (kind.* == .payload and (!values.namedHome(function, slot) or values.sharedRecord(program.records, local.ty))) kind.* = .none;
    }
    return kinds;
}

/// The local a `.field` projection reads, when the value is exactly that.
fn payloadFieldBase(program: typed.Program, value: typed.NodeId) ?typed.LocalId {
    const field = switch (program.nodes[@backingInt(value)].data) {
        .field => |field| field,
        else => return null,
    };
    return switch (program.nodes[@backingInt(field.base)].data) {
        .local => |base| base,
        else => null,
    };
}

/// A receiver write (`xs.append(v)`, `d[k] = v`, a `class` field update) or a
/// `mut` argument, and the local its receiver is read from.
fn expressionWrite(program: typed.Program, function: typed.Function, id: typed.NodeId) ?WriteSite {
    const node = program.nodes[@backingInt(id)];
    switch (node.data) {
        .call => |call| {
            const callee = program.functions[@backingInt(call.function)];
            for (callee.signature.declared_mutates) |position| {
                if (position >= call.arguments.len) continue;
                const root = mutation.nodeRoot(program, call.arguments[position]) orelse continue;
                return .{ .root = root, .span = program.nodes[@backingInt(call.arguments[position])].span };
            }
            return null;
        },
        else => {},
    }
    const witness = mutation.typedNode(program, function, node) orelse return null;
    if (witness.operation != .receiver_write) return null;
    return .{ .root = witness.owner orelse return null, .span = witness.span };
}

/// A field or element assignment `x.f = v` / `x[i] = v` on a value record or
/// fixed array, which rebuilds `x` from its own old value.
fn statementWrite(facts: *const values.Facts, id: typed.StatementId) ?WriteSite {
    const statement = facts.program.statements[@backingInt(id)];
    const store = switch (statement.data) {
        .assign => |store| store,
        else => return null,
    };
    switch (facts.program.nodes[@backingInt(store.value)].data) {
        .update, .replace => {},
        else => return null,
    }
    if (!facts.rootedAt(store.value, store.slot)) return null;
    return .{ .root = store.slot, .span = statement.span };
}

/// The value binding a write rooted at `slot` goes through: the slot itself,
/// or the binding a synthetic temporary was read from.
// twin-drift-ok: `values.namedRoot` follows temporaries to any named local;
// this walk stops at a binding and refuses a path through a `class` object.
fn bindingRoot(facts: *const values.Facts, slot: typed.LocalId, bindings: []const Binding) ?typed.LocalId {
    var current = slot;
    var hops: usize = 0;
    while (hops < 64) : (hops += 1) {
        const index = @backingInt(current);
        if (bindings[index] != .none) return current;
        if (!facts.synthetic[index]) return null;
        const value = facts.stores[index] orelse return null;
        // A path through a `class` object reaches shared storage.
        if (throughShared(facts.program, value)) return null;
        current = values.pathRoot(facts.program, value) orelse return null;
    }
    return null;
}

/// Whether a write rooted at `slot` changes (a path into) a function's
/// returned value: a temporary copy no name holds, so the write is lost.
fn temporaryRoot(facts: *const values.Facts, slot: typed.LocalId) bool {
    var current = slot;
    var hops: usize = 0;
    while (hops < 64) : (hops += 1) {
        const index = @backingInt(current);
        if (!facts.synthetic[index]) return false;
        const value = facts.stores[index] orelse return false;
        if (throughShared(facts.program, value)) return false;
        const base = pathBase(facts.program, value);
        switch (facts.program.nodes[@backingInt(base)].data) {
            .call, .invoke => return values.needsCopy(facts.program.records, facts.program.nodes[@backingInt(base)].ty),
            .local => |next| current = next,
            else => return false,
        }
    }
    return false;
}

fn bindingMessage(allocator: std.mem.Allocator, function: typed.Function, root: typed.LocalId, kind: Binding) Error![]const u8 {
    const name = function.scope.locals[@backingInt(root)].name;
    return switch (kind) {
        .loop => std.fmt.allocPrint(allocator, loop_write_text, .{ name, name }),
        .payload => std.fmt.allocPrint(allocator, payload_write_text, .{ name, name }),
        .none => allocator.dupe(u8, "this writes a copy"),
    };
}

/// Whether a read path crosses a field or element of a `class` object or
/// Cell, whose storage is shared rather than copied.
fn throughShared(program: typed.Program, id: typed.NodeId) bool {
    var current = id;
    var hops: usize = 0;
    while (hops < 64) : (hops += 1) {
        const base = switch (program.nodes[@backingInt(current)].data) {
            .field => |field| field.base,
            .index => |access| access.base,
            .unwrap, .cast, .wrap => |value| value,
            .propagate => |propagate| propagate.value,
            else => return false,
        };
        if (values.sharedRecord(program.records, program.nodes[@backingInt(base)].ty)) return true;
        current = base;
    }
    return false;
}

/// The node a read path (fields, indexes, unwraps) starts from.
// twin-drift-ok: `values.pathRoot` answers the root local and follows element
// reads; this answers the base node, which may be a call, and does not.
fn pathBase(program: typed.Program, id: typed.NodeId) typed.NodeId {
    var current = id;
    var hops: usize = 0;
    while (hops < 64) : (hops += 1) switch (program.nodes[@backingInt(current)].data) {
        .field => |field| current = field.base,
        .index => |access| current = access.base,
        .unwrap, .cast, .wrap => |value| current = value,
        .propagate => |propagate| current = propagate.value,
        else => return current,
    };
    return current;
}

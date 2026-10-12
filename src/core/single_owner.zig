//! Experimental source contract: lists move, calls borrow, and copies are explicit.
//! This check runs on complete typed trees before any optimization. It deliberately
//! refuses unsupported escapes instead of falling back to snapshot semantics.
const std = @import("std");
const language = @import("mylang");
const typed = language.typed;
const ir = @import("ir.zig");
const resources = @import("single_owner_resource.zig");
const Span = language.source.Span;
const none = std.math.maxInt(usize);
const zero_unsupported = "E_ZERO_RC_UNSUPPORTED";
const unsupported = "E_SINGLE_OWNER_UNSUPPORTED";
const borrow_error = "E_SINGLE_OWNER_BORROW";
const view_signature = "E_ZERO_RC_VIEW_SIGNATURE";
const view_escape = "E_ZERO_RC_VIEW_ESCAPE";
const view_unsupported = "E_ZERO_RC_VIEW_UNSUPPORTED";
const overlap_error = "E_SINGLE_OWNER_OVERLAP";
const resource_escape = "E_ZERO_RC_RESOURCE_ESCAPE";
const resource_origin = "E_ZERO_RC_RESOURCE_ORIGIN";
const resource_mode = "generic resource ownership requires checked zero-RC mode";

/// Match may consume a freshly produced union, never a local or a projection.
/// Shared by checking and lowering so the source rule does not depend on SSA use counts.
pub fn matchOwnsTemporary(nodes: []const typed.Node, id: typed.NodeId) bool {
    return switch (nodes[@backingInt(id)].data) {
        .call, .invoke, .variant => true,
        .block_value => |block| matchOwnsTemporary(nodes, block.value),
        .buffer_operation => |operation| switch (operation.kind) {
            .copy,
            .pop,
            .pop_key,
            .pop_default,
            .decode,
            .from_hex,
            .scalar_count,
            .scalar_count_range,
            .parse_int,
            .parse_float,
            .parse_int_range,
            .parse_float_range,
            => true,
            else => false,
        },
        else => false,
    };
}

/// A located refusal from the experimental language contract.
pub const Failure = struct {
    code: []const u8 = unsupported,
    message: []const u8 = "",
    span: Span = .{ .start = 0, .end = 0 },
};
/// Allocation failure or a source contract violation.
pub const Error = error{ OutOfMemory, Rejected };

/// Check and render a source refusal; false means the command must not continue.
pub fn validate(a: std.mem.Allocator, program: typed.Program, src: language.source.Source, format: language.diagnostic_output.Format, report: *std.ArrayList(u8)) error{OutOfMemory}!bool {
    return validateMode(a, program, src, format, report, false);
}

/// Validate the selected experimental ownership contract.
pub fn validateMode(a: std.mem.Allocator, program: typed.Program, src: language.source.Source, format: language.diagnostic_output.Format, report: *std.ArrayList(u8), zero_rc: bool) error{OutOfMemory}!bool {
    var failure: Failure = .{};
    checkMode(a, program, &failure, zero_rc) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Rejected => {
            try render(a, src, failure, format, report);
            return false;
        },
    };
    return true;
}

/// Validate every checked function, including bodies reached through callbacks.
pub fn check(a: std.mem.Allocator, program: typed.Program, failure: *Failure) Error!void {
    return checkMode(a, program, failure, false);
}

/// Zero-RC extends the move contract to every admitted owning leaf.
pub fn checkMode(a: std.mem.Allocator, program: typed.Program, failure: *Failure, zero_rc: bool) Error!void {
    const linear = try a.alloc(bool, program.records.len);
    @memset(linear, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (program.records, 0..) |record, index| {
            if (linear[index] or record.shape.builtin == .borrowed_view) continue;
            const owns = if (record.isCollection()) (record.collection.kind == .list or (zero_rc and (record.collection.kind == .string or record.collection.kind == .bytes or record.collection.kind == .dictionary))) else owns: {
                if (zero_rc and (record.collection.box or record.shape.resource != null)) break :owns true;
                for (record.fields) |field| if ((zero_rc and field.boxed) or isOwned(linear, field.ty, zero_rc)) break :owns true;
                if (record.shape.array) |array| if (isOwned(linear, array.element, zero_rc)) break :owns true;
                if (record.shape.variants) |variants| for (variants.cases) |case| {
                    if (case.payload) |payload| if ((zero_rc and case.boxed) or isOwned(linear, payload, zero_rc)) break :owns true;
                };
                break :owns false;
            };
            if (owns) {
                linear[index] = true;
                changed = true;
            }
        }
    }
    for (program.functions) |function| {
        var work = std.heap.ArenaAllocator.init(a);
        defer work.deinit();
        var c: Checker = .{
            .a = work.allocator(),
            .diagnostic_allocator = a,
            .program = program,
            .function = function,
            .linear = linear,
            .zero_rc = zero_rc,
            .failure = failure,
            .state = try work.allocator().alloc(State, function.scope.locals.len),
        };
        @memset(c.state, .{});
        for (function.scope.locals, 0..) |local, index| {
            try c.supported(local.ty, local.declaration, 0);
            if (index < function.signature.parameter_count and c.view(local.ty) and local.mutable) return c.reject(local.declaration, view_signature, "view parameters are read-only");
            if (index < function.signature.parameter_count) c.state[index] = .{
                .available = true,
                .borrowed = (isOwned(linear, local.ty, zero_rc) or typed.isBorrowedView(program.records, local.ty)) and !(zero_rc and resources.affine(program, local.ty)),
                .dependency = if (zero_rc and resources.dependent(program, local.ty)) index else none,
                .writable = local.mutable,
            };
        }
        try c.supported(function.signature.return_type, function.declaration, 0);
        if (zero_rc and resources.dependent(program, function.signature.return_type)) _ = try c.resourceParameter(function, function.declaration);
        if (typed.isBorrowedView(program.records, function.signature.return_type)) {
            _ = try c.returnSource(function, function.declaration);
            if (function.signature.declared_mutates.len != 0) return c.reject(function.declaration, view_signature, "a function returning a view cannot also take mut parameters in this prototype");
        }
        if (function.policy.c_abi or function.policy.host != null) {
            try c.foreign();
            continue;
        }
        _ = try c.checkStatement(function.scope.body);
    }
}

fn isLinear(linear: []const bool, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < linear.len and linear[ty.recordIndex()];
}

fn isOwned(linear: []const bool, ty: typed.Type, zero_rc: bool) bool {
    if (zero_rc and (ty.isFile() or owningCapability(ty))) return true;
    return isLinear(linear, ty);
}

fn owningCapability(ty: typed.Type) bool {
    return ty.capabilityIndex() != null and !ty.isStream() and ty != .host_cap;
}

const State = struct {
    available: bool = false,
    borrowed: bool = false,
    writable: bool = false,
    root: usize = none,
    view_definition: ?typed.NodeId = null,
    transferable: bool = false,
    dependency: usize = none,
};
const Access = enum { read, move, mutate, update };
const Loan = struct { root: usize, write: bool };
const Loop = struct { id: usize, before: []const State };

const Checker = struct {
    a: std.mem.Allocator,
    diagnostic_allocator: std.mem.Allocator,
    program: typed.Program,
    function: typed.Function,
    linear: []const bool,
    zero_rc: bool,
    failure: *Failure,
    state: []State,
    type_path: std.ArrayList(typed.Type) = .empty,
    loans: std.ArrayList(Loan) = .empty,
    loops: std.ArrayList(Loop) = .empty,

    fn reject(c: *Checker, span: Span, code: []const u8, message: []const u8) Error {
        c.failure.* = .{ .code = code, .message = message, .span = span };
        return error.Rejected;
    }

    fn foreign(c: *Checker) Error!void {
        const function = c.function;
        // Extern signatures are scalar-only. Native provider acquisitions
        // separately transfer handles into lexical owning scopes.
        if (c.zero_rc) {
            if (function.policy.host != null and !function.policy.c_abi) return c.reject(function.declaration, zero_unsupported, "copied Host adapters are retired; use an extern C contract");
            return;
        }
        for (function.scope.locals[0..function.signature.parameter_count]) |local| {
            if (isLinear(c.linear, local.ty)) return c.reject(function.declaration, "E_SINGLE_OWNER_ESCAPE", "a borrowed list cannot cross a foreign-function boundary in this prototype");
        }
        if (isLinear(c.linear, function.signature.return_type)) return c.reject(function.declaration, "E_SINGLE_OWNER_ESCAPE", "foreign list results are outside the single-owner prototype");
    }

    fn owns(c: *const Checker, ty: typed.Type) bool {
        return isOwned(c.linear, ty, c.zero_rc);
    }

    fn supported(c: *Checker, ty: typed.Type, span: Span, depth: usize) Error!void {
        if (c.zero_rc and depth != 0) if (ty.isFile() or owningCapability(ty)) return c.reject(span, zero_unsupported, "store resource owners in named local scopes in the zero-RC prototype");
        if (typed.isBorrowedView(c.program.records, ty)) {
            if (!c.zero_rc or depth != 0) return c.reject(span, view_escape, "borrowed views require zero-RC mode and cannot be stored inside aggregates");
            return;
        }
        if (!ty.isAggregate()) return;
        if (std.mem.indexOfScalar(typed.Type, c.type_path.items, ty) != null) return;
        try c.type_path.append(c.a, ty);
        defer _ = c.type_path.pop();
        const record = c.program.records[ty.recordIndex()];
        if (record.collection.box and !c.zero_rc) return c.reject(span, unsupported, "recursive boxes are outside the single-owner prototype");
        if (record.isCollection()) {
            if (record.collection.kind == .dictionary) {
                if (!c.zero_rc) return c.reject(span, unsupported, "dictionaries and sets are outside the single-owner prototype");
                try c.supported(record.collection.key.?, span, depth + 1);
                if (!record.collection.set) try c.supported(record.shape.buffer.?, span, depth + 1);
            }
            if (record.collection.kind == .list) try c.supported(record.shape.buffer.?, span, depth + 1);
            return;
        }
        if (!c.zero_rc and record.shape.variants != null and c.owns(ty)) return c.reject(span, unsupported, "unions containing lists are outside the single-owner prototype");
        try c.nestedTypes(record, span, depth);
    }

    fn nestedTypes(c: *Checker, record: typed.Record, span: Span, depth: usize) Error!void {
        for (record.fields) |field| {
            if (field.boxed and !c.zero_rc) return c.reject(span, unsupported, "recursive records are outside the single-owner prototype");
            try c.supported(field.ty, span, depth + 1);
        }
        if (record.shape.array) |array| try c.supported(array.element, span, depth + 1);
        if (record.shape.variants) |variants| for (variants.cases) |case| {
            if (case.payload) |payload| {
                if (c.zero_rc and variants.fallible and payload.isFile()) continue;
                try c.supported(payload, span, depth + 1);
            }
        };
        if (record.contract.callback) |callback| {
            for (callback.parameters) |parameter| try c.supported(parameter, span, depth + 1);
            try c.supported(callback.return_type, span, depth + 1);
        }
    }

    fn view(c: *const Checker, ty: typed.Type) bool {
        return typed.isBorrowedView(c.program.records, ty);
    }

    fn tracked(c: *const Checker, ty: typed.Type) bool {
        return c.owns(ty) or c.view(ty);
    }

    fn returnSource(c: *Checker, function: typed.Function, span: Span) Error!usize {
        var found: ?usize = null;
        for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index| {
            if (!c.view(local.ty)) continue;
            if (found != null or local.mutable) return c.reject(span, view_signature, "a returned view requires exactly one immutable view parameter");
            found = index;
        }
        return found orelse return c.reject(span, view_signature, "a returned view requires exactly one immutable view parameter");
    }

    fn invalidateViews(c: *Checker, root: usize) void {
        for (c.state, c.function.scope.locals, 0..) |*state, local, slot| {
            if (slot != root and state.available and c.view(local.ty) and c.rootOf(slot) == root) state.available = false;
        }
    }

    fn rootOf(c: *const Checker, slot: usize) usize {
        var result = slot;
        var remaining = c.state.len;
        while (c.state[result].root != none and remaining != 0) : (remaining -= 1) result = c.state[result].root;
        return result;
    }

    fn checkLocal(c: *Checker, slot: usize, access: Access, span: Span) Error!void {
        const local = c.function.scope.locals[slot];
        if (!c.tracked(local.ty)) return;
        const root = c.rootOf(slot);
        if (!c.state[slot].available or !c.state[root].available) {
            if (c.view(local.ty)) return c.reject(span, "E_ZERO_RC_VIEW_INVALIDATED", "this view was invalidated by a move, mutation, replacement, or incompatible branch; copy it before changing its owner");
            const message = try std.fmt.allocPrint(c.diagnostic_allocator, "'{s}' was moved or is unavailable on this path; use .copy() when both values are needed", .{local.name});
            return c.reject(span, "E_SINGLE_OWNER_MOVED", message);
        }
        if (c.view(local.ty) and access != .read) return c.reject(span, view_escape, "views are read-only; use .copy() for independent owned storage");
        const write = access != .read;
        if (c.zero_rc) try c.resourceAccess(slot, root, write, span);
        for (c.loans.items) |loan| if (loan.root == root and (loan.write or write)) {
            return c.reject(span, overlap_error, "a value cannot be moved or mutated while another argument or iteration borrows it");
        };
        if (access == .move) {
            if (c.state[slot].borrowed) {
                if (!c.state[slot].transferable or c.state[root].borrowed) return c.reject(span, borrow_error, "a borrowed value cannot be stored or returned; make an explicit .copy()");
                c.state[root].available = false;
            }
            c.invalidateViews(root);
            c.state[slot].available = false;
        } else if (access == .mutate or access == .update) {
            if (!c.state[slot].writable or !c.state[root].writable) return c.reject(span, borrow_error, "mutation requires an exclusive mut parameter or a mutable owning local");
            c.invalidateViews(root);
        }
    }

    fn origin(c: *Checker, id: typed.NodeId) ?usize {
        const node = c.program.nodes[@backingInt(id)];
        return switch (node.data) {
            .local => |slot| c.rootOf(@backingInt(slot)),
            .field => |field| c.origin(field.base),
            .index => |index| if (c.freshCharacter(index.base)) null else c.origin(index.base),
            .cast => |value| if (c.zero_rc and c.program.nodes[@backingInt(value)].ty != node.ty) null else c.origin(value),
            .wrap, .unwrap => |value| c.origin(value),
            .block_value => |block| c.origin(block.value),
            .buffer_operation => |operation| switch (operation.kind) {
                .read => if (c.zero_rc and c.program.records[c.function.scope.locals[@backingInt(operation.owner)].ty.recordIndex()].collection.kind == .string) null else c.rootOf(@backingInt(operation.owner)),
                .get, .key_at, .value_at, .borrow_view => c.rootOf(@backingInt(operation.owner)),
                .slice => if (c.view(node.ty)) c.rootOf(@backingInt(operation.owner)) else null,
                else => null,
            },
            .call => |call| blk: {
                if (!c.view(node.ty)) break :blk null;
                const function = c.program.functions[@backingInt(call.function)];
                for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index| {
                    if (c.view(local.ty)) break :blk c.origin(call.arguments[index]);
                }
                break :blk null;
            },
            else => null,
        };
    }

    /// Only the exact projection reconstructed by its parent may write in place.
    fn sameFieldWriteback(c: *const Checker, base: typed.NodeId, field: typed.FieldInit) bool {
        const nested = c.program.nodes[@backingInt(field.value)];
        const nested_base = switch (nested.data) {
            .update => |update| update.base,
            .replace => |replace| replace.base,
            else => return false,
        };
        return switch (c.program.nodes[@backingInt(nested_base)].data) {
            .field => |projection| projection.base == base and projection.index == field.index,
            else => false,
        };
    }

    fn freshCharacter(c: *const Checker, base: typed.NodeId) bool {
        const ty = c.program.nodes[@backingInt(base)].ty;
        return c.zero_rc and ty.isAggregate() and c.program.records[ty.recordIndex()].collection.kind == .string;
    }

    fn wholeOwner(c: *const Checker, id: typed.NodeId) bool {
        return switch (c.program.nodes[@backingInt(id)].data) {
            .local => |slot| c.state[@backingInt(slot)].root == none or c.state[@backingInt(slot)].transferable,
            .block_value => |block| c.wholeOwner(block.value),
            else => false,
        };
    }

    fn temporary(c: *const Checker, slot: usize) bool {
        const local = c.function.scope.locals[slot];
        // A conditional joins owners from its branches; it is not a receiver loan.
        if (std.mem.eql(u8, local.name, "<conditional>")) return false;
        return std.mem.startsWith(u8, local.name, "<") or local.origin == .iteration or local.origin == .pattern;
    }

    fn checkStore(c: *Checker, store: typed.Store, initializing: bool, span: Span) Error!void {
        const slot = @backingInt(store.slot);
        const local = c.function.scope.locals[slot];
        if (c.view(local.ty)) {
            if (local.mutable and !c.temporary(slot)) return c.reject(span, view_unsupported, "view bindings are immutable in this prototype; create a new const view");
            try c.expression(store.value, .read);
            const source = c.origin(store.value) orelse return c.reject(span, view_escape, "a view must borrow from a known local owner or view parameter");
            c.state[slot] = .{ .available = true, .borrowed = true, .root = if (source == slot) none else source, .view_definition = store.value };
            return;
        }
        if (!c.owns(local.ty)) {
            try c.expression(store.value, .read);
            return;
        }
        // The front end introduces receiver/iteration aliases. They are temporary
        // loans, not source assignments, and cannot themselves escape.
        if (c.temporary(slot)) {
            if (c.origin(store.value)) |source| {
                try c.expression(store.value, .read);
                if (source == slot) return;
                c.state[slot] = .{
                    .available = true,
                    .borrowed = true,
                    .writable = local.origin != .iteration and c.state[source].writable,
                    .root = source,
                    .transferable = c.wholeOwner(store.value),
                    .dependency = c.state[source].dependency,
                };
                return;
            }
        }
        const node = c.program.nodes[@backingInt(store.value)];
        const updating = !initializing and (store.element or node.data == .update or node.data == .replace);
        if (updating) {
            try c.checkLocal(slot, .mutate, span);
            try c.expression(store.value, .update);
        } else {
            if (!initializing and c.state[slot].available) try c.checkLocal(slot, .mutate, span);
            try c.expression(store.value, .move);
        }
        const parameter = slot < c.function.signature.parameter_count;
        const affine = c.zero_rc and resources.affine(c.program, local.ty);
        const dependency = if (c.zero_rc and resources.dependent(c.program, local.ty)) try c.resourceOrigin(store.value) else null;
        c.state[slot] = .{ .available = true, .borrowed = parameter and !affine, .writable = local.mutable, .dependency = dependency orelse none };
    }

    fn expression(c: *Checker, id: typed.NodeId, access: Access) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        if (c.view(node.ty) and access != .read) return c.reject(node.span, view_escape, "views cannot be moved into owning storage; use .copy()");
        switch (node.data) {
            .integer, .boolean, .unit, .blob, .function_value => {},
            .local => |slot| try c.checkLocal(@backingInt(slot), access, node.span),
            .block_value => |block| {
                _ = try c.checkStatement(block.body);
                try c.expression(block.value, access);
            },
            .cast => |value| {
                const from = c.program.nodes[@backingInt(value)].ty;
                if (from != node.ty and (c.view(from) or c.view(node.ty))) return c.reject(node.span, view_unsupported, "view conversions require an explicit .copy()");
                try c.expression(value, if (c.zero_rc and from != node.ty) .read else access);
            },
            .wrap, .unwrap, .arena_escape => |value| try c.expression(value, access),
            .length => |value| try c.expression(value, .read),
            .unary => |unary| try c.expression(unary.operand, .read),
            .binary => |binary| {
                const view_operand = c.view(c.program.nodes[@backingInt(binary.left)].ty) or c.view(c.program.nodes[@backingInt(binary.right)].ty);
                if (view_operand) return c.reject(node.span, view_unsupported, "view binary operations are outside this prototype; use .copy()");
                try c.expression(binary.left, .read);
                const saved = c.loans.items.len;
                defer c.loans.shrinkRetainingCapacity(saved);
                if (c.tracked(c.program.nodes[@backingInt(binary.left)].ty)) {
                    if (c.origin(binary.left)) |root| try c.loans.append(c.a, .{ .root = root, .write = false });
                }
                // Conservatively join short-circuit paths: a move on the RHS
                // makes its source unavailable after the expression.
                try c.expression(binary.right, .read);
            },
            .field => |field| {
                if (access == .move and c.owns(node.ty)) return c.reject(node.span, borrow_error, "moving a field out of a record is outside this prototype; use .copy() or pass the field to a helper");
                try c.expression(field.base, if (access == .mutate or access == .update) .mutate else .read);
            },
            .index => |index| {
                const base = c.program.nodes[@backingInt(index.base)].ty;
                const fresh_character = c.zero_rc and base.isAggregate() and c.program.records[base.recordIndex()].collection.kind == .string;
                if (!fresh_character and access == .move and c.owns(node.ty)) return c.reject(node.span, borrow_error, "an indexed value is borrowed; use .copy() or pop() to obtain an owned value");
                try c.expression(index.base, .read);
                const saved = c.loans.items.len;
                defer c.loans.shrinkRetainingCapacity(saved);
                if (c.origin(index.base)) |root| try c.loans.append(c.a, .{ .root = root, .write = false });
                try c.expression(index.index, .read);
            },
            .array => |items| for (items) |item| try c.expression(item, .move),
            .record => |fields| try c.recordFields(fields),
            .update => |update| {
                try c.expression(update.base, if (access == .update) .mutate else .move);
                for (update.fields) |field| try c.expression(field.value, if (access == .update and c.sameFieldWriteback(update.base, field)) .update else .move);
            },
            .replace => |replace| {
                try c.expression(replace.base, if (access == .update) .mutate else .move);
                try c.expression(replace.index, .read);
                try c.expression(replace.value, .move);
            },
            .acquire_buffer => |buffer| try c.expression(buffer.capacity, .read),
            .buffer_operation => try c.collection(node, access),
            .call => |call| {
                if (call.evaluation != null) return c.reject(node.span, unsupported, "calls requiring argument-evaluation temporaries are outside this prototype; bind the arguments first");
                const function = c.program.functions[@backingInt(call.function)];
                try c.arguments(call.arguments, call.evaluation_order, function.signature.declared_mutates);
            },
            .invoke => |call| {
                if (call.evaluation != null) return c.reject(node.span, unsupported, "bind callback arguments before calling in this prototype");
                try c.expression(call.callee, .read);
                const callback = c.program.records[c.program.nodes[@backingInt(call.callee)].ty.recordIndex()].contract.callback.?;
                try c.arguments(call.arguments, call.evaluation_order, callback.mutates);
            },
            .print => |print| {
                for (print.arguments) |argument| {
                    const ty = c.program.nodes[@backingInt(argument)].ty;
                    if (c.view(ty) and c.program.records[ty.recordIndex()].collection.kind == .bytes)
                        return c.reject(node.span, view_unsupported, "printing ByteView requires an explicit .copy() in this prototype");
                }
                if (print.stream) |stream| try c.expression(stream, .read);
                var values: std.ArrayList(typed.NodeId) = .empty;
                try values.appendSlice(c.a, print.arguments);
                if (print.separator) |separator| try values.append(c.a, separator);
                if (print.terminator) |terminator| try values.append(c.a, terminator);
                try c.arguments(values.items, &.{}, &.{});
            },
            .stream_write => |write| {
                try c.expression(write.stream, .read);
                try c.expression(write.text, .read);
            },
            .stand_in,
            .external_read,
            .environment_get,
            .environment_names,
            .dir_resource,
            .host_resource,
            .restrict_resource,
            .environment_only,
            .file_access,
            .file_method,
            .acquire_resource,
            .complete_resource,
            .resource_io,
            => try c.resourceExpression(node),
            .propagate => |value| try c.propagateResource(value.value, node.span),
            .variant => |variant| if (variant.value) |value| try c.expression(value, .move),
        }
    }

    fn recordFields(c: *Checker, fields: []const typed.FieldInit) Error!void {
        const saved = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(saved);
        for (fields) |field| {
            try c.expression(field.value, .move);
            if (c.zero_rc) if (try c.resourceOrigin(field.value)) |anchor|
                try c.loans.append(c.a, .{ .root = anchor, .write = false });
        }
    }

    fn resourceExpression(c: *Checker, node: typed.Node) Error!void {
        switch (node.data) {
            .stand_in => |stand| {
                try c.expression(stand.first, .read);
                if (stand.second) |second| try c.expression(second, .read);
            },
            .external_read => |read| try c.expression(read.capability, .read),
            .environment_get => |get| {
                try c.expression(get.capability, .read);
                try c.expression(get.name, .read);
            },
            .environment_names => |cap| try c.expression(cap, .read),
            .dir_resource, .host_resource, .restrict_resource, .environment_only => return c.reject(node.span, zero_unsupported, "dependent capabilities require a with scope in zero-RC mode"),
            .file_access => |file| try c.arguments(file.arguments, &.{}, &.{}),
            .file_method => |file| {
                try c.checkLocal(@backingInt(file.owner), .read, node.span);
                if (file.argument) |argument| try c.expression(argument, .read);
            },
            .acquire_resource => |acquire| {
                if (!c.zero_rc) return c.reject(node.span, unsupported, resource_mode);
                try c.arguments(&.{ acquire.capability, acquire.request }, &.{}, &.{});
                _ = c.origin(acquire.capability) orelse return c.reject(node.span, resource_origin, "bind the provider to a named local before acquiring a resource");
            },
            .complete_resource => |owner| {
                if (!c.zero_rc) return c.reject(node.span, unsupported, resource_mode);
                try c.expression(owner, .move);
            },
            .resource_io => |io| {
                if (!c.zero_rc) return c.reject(node.span, unsupported, resource_mode);
                try c.checkLocal(@backingInt(io.owner), .read, node.span);
                if (io.value) |input| try c.expression(input, .read);
            },
            else => unreachable,
        }
    }

    fn propagateResource(c: *Checker, value: typed.NodeId, span: Span) Error!void {
        try c.expression(value, .move);
        if (!c.zero_rc) return;
        const shape = typed.resultShape(c.program.nodes[@backingInt(value)].ty, c.program.records) orelse return;
        if (resources.dependent(c.program, shape.error_type)) try c.resourceReturn(value, span);
    }

    fn resourceReturn(c: *Checker, value: typed.NodeId, span: Span) Error!void {
        const anchor = try c.resourceParameter(c.function, span);
        if (try c.resourceOrigin(value)) |actual| if (actual != anchor)
            return c.reject(span, resource_escape, "a returned resource must depend on this function's single provider or resource input");
    }

    fn resourceParameter(c: *Checker, function: typed.Function, span: Span) Error!usize {
        return resources.parameter(c.program, function) orelse return c.reject(span, resource_origin, "a resource result requires exactly one provider or resource input");
    }

    fn resourceOrigin(c: *Checker, id: typed.NodeId) Error!?usize {
        const node = c.program.nodes[@backingInt(id)];
        if (resources.provider(node.ty)) return c.origin(id);
        if (!resources.dependent(c.program, node.ty)) return null;
        return switch (node.data) {
            .local => |slot| if (c.state[@backingInt(slot)].dependency == none) null else c.state[@backingInt(slot)].dependency,
            .field => |field| c.resourceOrigin(field.base),
            .block_value => |block| c.resourceOrigin(block.value),
            .wrap, .unwrap, .cast, .complete_resource => |value| c.resourceOrigin(value),
            .propagate => |value| c.resourceOrigin(value.value),
            .variant => |variant| if (variant.value) |value| c.resourceOrigin(value) else null,
            .file_access => |file| c.origin(file.arguments[0]) orelse return c.reject(node.span, resource_origin, "a file requires a named provider"),
            .acquire_resource => |acquire| c.origin(acquire.capability) orelse return c.reject(node.span, resource_origin, "a resource requires a named provider"),
            .call => |call| c.resourceOrigin(call.arguments[try c.resourceParameter(c.program.functions[@backingInt(call.function)], node.span)]),
            .record => |fields| result: {
                var anchor: ?usize = null;
                for (fields) |field| if (try c.resourceOrigin(field.value)) |next| {
                    if (anchor != null and anchor != next) return c.reject(node.span, resource_origin, "one resource carrier cannot combine different provider origins");
                    anchor = next;
                };
                break :result anchor;
            },
            else => c.reject(node.span, resource_origin, "this resource origin is outside the local checked contract"),
        };
    }

    fn resourceAccess(c: *Checker, slot: usize, root: usize, write: bool, span: Span) Error!void {
        const dependency = c.state[slot].dependency;
        if (dependency != none and resources.provider(c.function.scope.locals[dependency].ty) and !c.state[dependency].available)
            return c.reject(span, resource_escape, "the resource's provider is no longer available");
        if (!write or !resources.provider(c.function.scope.locals[root].ty)) return;
        for (c.state, c.function.scope.locals, 0..) |state, local, other| {
            if (state.available and c.state[c.rootOf(other)].available and state.dependency == root and resources.dependent(c.program, local.ty))
                return c.reject(span, resource_escape, "a provider cannot move or change while a dependent resource is live");
        }
    }

    fn collection(c: *Checker, node: typed.Node, access: Access) Error!void {
        const operation = node.data.buffer_operation;
        if (c.zero_rc and (operation.kind == .snapshot or operation.kind == .view))
            return c.reject(node.span, zero_unsupported, "shared snapshots and retained views are unsupported; use .borrow() for a checked view or .copy() for ownership");
        const owner = @backingInt(operation.owner);
        if (operation.kind == .copy) return c.checkLocal(owner, .read, node.span);
        const linear = c.tracked(c.function.scope.locals[owner].ty);
        if (linear and operation.kind == .iteration_check) {
            try c.checkLocal(owner, .read, node.span);
            const root = c.rootOf(owner);
            const exists = for (c.loans.items) |loan| {
                if (loan.root == root) break true;
            } else false;
            if (!exists) try c.loans.append(c.a, .{ .root = root, .write = false });
        } else {
            const write = operation.kind.writesReceiver();
            const writable_projection = c.owns(node.ty) and (access == .mutate or access == .update);
            try c.checkLocal(owner, if (write or writable_projection) .mutate else .read, node.span);
            const saved = c.loans.items.len;
            defer c.loans.shrinkRetainingCapacity(saved);
            // Operands finish before the operation mutates. Permit reads (including
            // the generated negative-index length check), but forbid invalidation.
            if (linear) try c.loans.append(c.a, .{ .root = c.rootOf(owner), .write = false });
            const schema = c.program.records[c.function.scope.locals[owner].ty.recordIndex()];
            const borrowed_read = switch (operation.kind) {
                .read, .get => schema.collection.kind == .list or schema.collection.kind == .dictionary,
                .key_at, .value_at, .setdefault => schema.collection.kind == .dictionary,
                else => false,
            };
            if (linear and access == .move and c.owns(node.ty) and borrowed_read) {
                return c.reject(node.span, borrow_error, "an element read is borrowed; use .copy() or pop() to obtain an owned value");
            }
            for (operation.arguments, 0..) |argument, index| {
                const consumes = if (schema.collection.kind == .dictionary) switch (operation.kind) {
                    .write, .setdefault => true,
                    .pop_default => index == 1,
                    else => false,
                } else operation.kind == .append or (operation.kind == .write and index == 1) or (operation.kind == .insert and index == 1);
                try c.expression(argument, if (consumes) .move else .read);
            }
            // These methods implicitly duplicate elements. Nested owned
            // lists need an explicit deep copy, which .copy() provides.
            const duplicates = switch (operation.kind) {
                .extend, .slice, .slice_step => !c.zero_rc,
                .insert, .remove, .pop_at, .reverse => !c.zero_rc,
                else => false,
            };
            if (linear and duplicates) {
                const record = c.program.records[c.function.scope.locals[owner].ty.recordIndex()];
                if (record.collection.kind == .list and c.owns(record.shape.buffer.?)) return c.reject(node.span, unsupported, "this method duplicates nested lists; use explicit .copy() and append/pop in the prototype");
            }
        }
    }

    fn arguments(c: *Checker, args: []const typed.NodeId, order: []const usize, mutates: []const u16) Error!void {
        const saved = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(saved);
        for (0..args.len) |position| {
            const index = if (order.len == 0) position else order[position];
            const write = std.mem.indexOfScalar(u16, mutates, @intCast(index)) != null;
            const arg = args[index];
            const affine = c.zero_rc and resources.affine(c.program, c.program.nodes[@backingInt(arg)].ty);
            try c.expression(arg, if (write) .mutate else if (affine) .move else .read);
            if (affine) if (try c.resourceOrigin(arg)) |provider| try c.loans.append(c.a, .{ .root = provider, .write = false });
            if (c.tracked(c.program.nodes[@backingInt(arg)].ty)) {
                if (c.origin(arg)) |root| try c.loans.append(c.a, .{ .root = root, .write = write });
            }
        }
    }

    fn merge(c: *Checker, first: []const State, second: []const State) void {
        for (c.state, first, second) |*out, left, right| {
            out.* = left;
            out.available = left.available and right.available;
            // Only compiler-created loans have roots. A differing root cannot
            // describe one definite borrowed value after this join.
            const same_ownership = left.root == right.root and left.borrowed == right.borrowed and left.transferable == right.transferable;
            if (!same_ownership or left.view_definition != right.view_definition or left.dependency != right.dependency) out.available = false;
        }
    }

    fn loopBack(c: *Checker, before: []const State, span: Span) Error!void {
        for (before, c.state, c.function.scope.locals) |old, now, local| {
            if (old.available and !now.available and c.view(local.ty)) return c.reject(span, "E_ZERO_RC_VIEW_INVALIDATED", "a loop cannot invalidate a view created outside it in this prototype; create the view inside the loop or copy it");
            const lost_owner = old.available and !old.borrowed and !now.available;
            if (lost_owner and c.owns(local.ty)) return c.reject(span, "E_SINGLE_OWNER_LOOP", "a value moved inside a loop must be reinitialized before the next iteration or loop exit");
        }
    }

    fn loop(c: *Checker, value: typed.Loop, span: Span) Error!void {
        const entry = try c.a.dupe(State, c.state);
        try c.expression(value.condition, .read);
        try c.loopBack(entry, span);
        const before = try c.a.dupe(State, c.state);
        const saved = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(saved);
        try c.loops.append(c.a, .{ .id = value.id, .before = before });
        defer _ = c.loops.pop();
        const falls = try c.checkStatement(value.body);
        if (falls) {
            if (value.step) |step| _ = try c.checkStatement(step);
            try c.loopBack(before, span);
        }
        // A loop may execute zero times. Outer owners remain available only
        // when every reachable path preserves them.
        const after = try c.a.dupe(State, c.state);
        c.merge(before, if (falls) after else before);
    }

    fn matchArms(c: *Checker, value: typed.NodeId, arms: []const typed.MatchArm) Error!bool {
        const owned = c.zero_rc and (matchOwnsTemporary(c.program.nodes, value) or resources.affine(c.program, c.program.nodes[@backingInt(value)].ty));
        try c.expression(value, if (owned) .move else .read);
        const dependency = if (c.zero_rc) try c.resourceOrigin(value) else null;
        const before = try c.a.dupe(State, c.state);
        const saved = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(saved);
        const source = c.origin(value);
        if (source) |root| try c.loans.append(c.a, .{ .root = root, .write = false });
        var joined: ?[]State = null;
        for (arms) |arm| {
            @memcpy(c.state, before);
            if (arm.slot) |slot| c.state[@backingInt(slot)] = .{ .available = true, .borrowed = !owned, .root = if (owned) none else source orelse none, .dependency = dependency orelse none };
            const body = if (owned and arm.unpack != null) unpacked: {
                // This is the whole hidden payload, split before source statements.
                // Each binding is now its own owner; the original is unavailable.
                if (arm.slot) |slot| c.state[@backingInt(slot)].available = false;
                for (arm.unpack.?.fields) |field| if (field) |slot| {
                    c.state[@backingInt(slot)] = .{ .available = true, .dependency = dependency orelse none };
                };
                break :unpacked arm.unpack.?.body;
            } else arm.body;
            if (!try c.checkStatement(body)) continue;
            if (arm.slot) |slot| c.state[@backingInt(slot)].available = false;
            if (arm.unpack) |unpack| for (unpack.fields) |field| if (field) |slot| {
                c.state[@backingInt(slot)].available = false;
            };
            if (joined) |previous| c.merge(previous, c.state);
            if (joined == null) joined = try c.a.alloc(State, c.state.len);
            @memcpy(joined.?, c.state);
        }
        if (joined) |after| @memcpy(c.state, after);
        return joined != null;
    }

    fn checkStatement(c: *Checker, id: typed.StatementId) Error!bool {
        const statement = c.program.statements[@backingInt(id)];
        switch (statement.data) {
            .block => |items| {
                for (items) |item| if (!try c.checkStatement(item)) return false;
            },
            .initialize => |store| try c.checkStore(store, true, statement.span),
            .assign => |store| try c.checkStore(store, false, statement.span),
            .discard => |value| try c.expression(value, if (c.zero_rc and resources.affine(c.program, c.program.nodes[@backingInt(value)].ty)) .move else .read),
            .ret => |value| {
                if (c.view(c.function.signature.return_type)) {
                    try c.expression(value, .read);
                    const source = try c.returnSource(c.function, statement.span);
                    if (c.origin(value) != source) return c.reject(statement.span, view_escape, "the returned view must borrow from this function's single view parameter");
                } else {
                    try c.expression(value, .move);
                    if (c.zero_rc and resources.dependent(c.program, c.function.signature.return_type)) try c.resourceReturn(value, statement.span);
                }
                return false;
            },
            .assertion => |assertion| {
                try c.expression(assertion.condition, .read);
                if (assertion.message_value) |message| try c.expression(message, .read);
            },
            .branch => |branch| {
                try c.expression(branch.condition, .read);
                const before = try c.a.dupe(State, c.state);
                const first_falls = try c.checkStatement(branch.then_body);
                const first = try c.a.dupe(State, c.state);
                @memcpy(c.state, before);
                const second_falls = if (branch.else_body) |body| try c.checkStatement(body) else true;
                if (first_falls and second_falls) {
                    const second = try c.a.dupe(State, c.state);
                    c.merge(first, second);
                } else if (first_falls) @memcpy(c.state, first);
                return first_falls or second_falls;
            },
            .with_scope => |scope| {
                const source = scope.resource orelse return c.reject(statement.span, zero_unsupported, "zero-RC scopes require an explicit file owner");
                const node = c.program.nodes[@backingInt(source)];
                const provider = @import("build_cap.zig").scopeProvider(c.program, source) orelse return c.reject(statement.span, zero_unsupported, "open a dependent scope directly from a named provider in this prototype");
                if (c.program.nodes[@backingInt(provider)].data != .local) return c.reject(statement.span, zero_unsupported, "bind the provider to a local before opening a scoped file");
                if (node.data == .file_access or node.data == .propagate) {
                    try c.expression(source, .read);
                } else {
                    switch (node.data) {
                        .dir_resource => |dir| try c.arguments(&.{ provider, dir.path }, &.{}, &.{}),
                        .host_resource => |host| try c.arguments(&.{ provider, host.name }, &.{}, &.{}),
                        .environment_only => |only| try c.arguments(&.{ provider, only.names }, &.{}, &.{}),
                        .restrict_resource => try c.expression(provider, .read),
                        else => try c.expression(source, .read),
                    }
                }
                const saved = c.loans.items.len;
                defer c.loans.shrinkRetainingCapacity(saved);
                if (c.origin(provider)) |root| try c.loans.append(c.a, .{ .root = root, .write = false });
                const slot = @backingInt(scope.slot);
                c.state[slot] = .{ .available = true, .borrowed = true };
                const falls = try c.checkStatement(scope.body);
                for (c.state, 0..) |*state, other| if (state.available and state.dependency == slot) {
                    if (other < slot) return c.reject(statement.span, resource_escape, "a resource cannot escape its provider scope");
                    state.available = false;
                };
                c.state[slot].available = false;
                return falls;
            },
            .match => |value| return c.matchArms(value.value, value.arms),
            .loop => |value| try c.loop(value, statement.span),
            .range_loop => |range| {
                const plan = range.plan();
                try c.checkStore(plan.start, true, statement.span);
                try c.checkStore(plan.end, true, statement.span);
                for (plan.setup) |setup| _ = try c.checkStatement(setup);
                try c.loop(plan.loop, statement.span);
            },
            .loop_exit => |exit| {
                for (c.loops.items) |frame| if (frame.id == exit.target) try c.loopBack(frame.before, statement.span);
                return false;
            },
        }
        return true;
    }
};

/// Whether an IR value contains an exclusively owned list, for backend guards.
pub fn containsList(module: *const ir.Module, ty: ir.Type) bool {
    if (module.zero_rc and (ty == .str or ty == .bytes or ty == .byte_buffer)) return true;
    if (!ty.isCompound()) return false;
    return switch (module.compound(ty)) {
        .list => true,
        .dict, .box => module.zero_rc,
        .@"union" => |cases| for (cases) |payload| {
            if (containsList(module, payload)) break true;
        } else false,
        .record => |fields| for (fields) |field| {
            if (containsList(module, field)) break true;
        } else false,
        .array => |array| containsList(module, array.elem),
        else => false,
    };
}

/// Opt a snapshot's list type and every reachable child-list type into COW.
/// Type-wide selection avoids introducing alias/escape inference into the experiment.
pub fn enableSnapshots(a: std.mem.Allocator, module: *ir.Module, ty: ir.Type) error{OutOfMemory}!void {
    if (!ty.isCompound()) return;
    switch (module.compound(ty)) {
        .list => |element| {
            if (std.mem.indexOfScalar(ir.Type, module.shared_lists.items, ty) != null) return;
            try module.shared_lists.append(a, ty);
            try enableSnapshots(a, module, element);
        },
        .record => |fields| for (fields) |field| try enableSnapshots(a, module, field),
        .array => |array| try enableSnapshots(a, module, array.elem),
        else => {},
    }
}

/// Whether retaining this value would share a list outside the snapshot families.
pub fn containsExclusiveList(module: *const ir.Module, ty: ir.Type) bool {
    if (module.zero_rc and (ty == .str or ty == .bytes or ty == .byte_buffer)) return true;
    if (!ty.isCompound()) return false;
    return switch (module.compound(ty)) {
        .list => module.exclusiveList(ty),
        .record => |fields| for (fields) |field| {
            if (containsExclusiveList(module, field)) break true;
        } else false,
        .array => |array| containsExclusiveList(module, array.elem),
        else => false,
    };
}

/// Fail closed if a lowering still needs to share an exclusive value. This
/// prototype never silently reintroduces COW for an unsupported compiler shape.
pub fn verifyLowered(module: *const ir.Module, failure: *Failure) error{Rejected}!void {
    for (module.functions.items) |function| for (function.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = function.inst(ref);
        // Verify builds intentionally assert uniqueness before updates/frees.
        // Those checks do not implement COW and are allowed here.
        if (module.zero_rc and (inst.op == .retain or inst.op == .is_unique)) {
            failure.* = .{ .code = "E_ZERO_RC_LOWERING", .message = "this lowering still requires reference counting; use an explicit owned copy or simplify the expression", .span = .{ .start = inst.span, .end = inst.span } };
            return error.Rejected;
        }
        if (inst.op != .retain) continue;
        if (!containsExclusiveList(module, function.inst(function.resolve(inst.a)).ty)) continue;
        failure.* = .{
            .code = "E_SINGLE_OWNER_LOWERING",
            .message = "this lowering still needs shared list storage; simplify the expression or use explicit .copy()",
            .span = .{ .start = inst.span, .end = inst.span },
        };
        return error.Rejected;
    };
}

/// Render the same located diagnostic for check, dump-ir, build and run.
pub fn render(a: std.mem.Allocator, src: language.source.Source, failure: Failure, format: language.diagnostic_output.Format, report: *std.ArrayList(u8)) error{OutOfMemory}!void {
    const diagnostic: language.diagnostic.Diagnostic = .{ .severity = .err, .code = failure.code, .span = failure.span, .message = failure.message };
    try report.appendSlice(a, try language.diagnostic_output.render(a, diagnostic, src, format));
}

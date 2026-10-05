//! D1 live iteration reads a place again after each step, retaining its indices.
const std = @import("std");
const source = @import("source.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const collections = @import("collection_lower.zig");
const loop_rebinding = @import("loop_rebinding.zig");
const operations = @import("buffer_operations.zig");
const Error = @import("diagnostic.zig").Error;

/// Prepared entry statements and the refresh preceding each live-place guard.
pub const Source = struct {
    setup: []const typed.StatementId,
    refresh: []const typed.StatementId = &.{},
    growing: bool = false,
    checking: bool = true,
};

/// Prepare an iteration receiver. Root rebinding takes an entry copy;
/// writes below a stable root read the current place, with indices evaluated once.
pub fn prepare(comptime Checker: type, b: collections.Builder(Checker), input: typed.NodeId, owner: typed.LocalId, body: ?ast.StatementId) Error!Source {
    const checker = b.checker;
    const schema = checker.catalog.records[checker.locals.items[@backingInt(owner)].ty.recordIndex()];
    const checking = schema.shape.array == null;
    const root = rootOf(Checker, checker, input, 0);
    if (root == null or body == null) return entry(Checker, b, owner, input, checking);
    if (schema.collection.kind == .string or typed.isByteString(schema)) return entry(Checker, b, owner, input, checking);
    const name = checker.locals.items[@backingInt(root.?)].name;
    const syntax: loop_rebinding.Syntax = .{ .program = checker.syntax, .src = checker.src };
    if (try loop_rebinding.rebinds(checker.allocator, syntax, body.?, name)) {
        if (!checking) {
            // An inline array snapshot is an independent semantic home, so
            // lowering copies its managed children rather than borrowing them.
            checker.locals.items[@backingInt(owner)].origin = .iteration;
            return entry(Checker, b, owner, input, false);
        }
        const copy = try b.access(input, .copy, &.{}, false);
        return entry(Checker, b, owner, try b.node(copy.ty, copy.data), true);
    }
    if (!try changes(Checker, checker, body.?, name)) return entry(Checker, b, owner, input, checking);
    var path: Path(Checker) = .{ .b = b };
    const value = try path.rebuild(input, 0);
    try path.setup.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = value } }));
    try path.refresh.append(checker.allocator, try b.stmt(.{ .assign = .{ .slot = owner, .value = value } }));
    // The back edge reads the root again, so a named field transfer cannot
    // mistake its body read for the root's last read (D1-LIVE-PLACE).
    checker.locals.items[@backingInt(root.?)].usage.reads += 1;
    return .{
        .setup = try path.setup.toOwnedSlice(checker.allocator),
        .refresh = try path.refresh.toOwnedSlice(checker.allocator),
        .growing = checking and (schema.collection.kind == .list or (schema.collection.kind == .bytes and !typed.isByteString(schema))),
        .checking = checking,
    };
}

/// Combine an iteration source's entry with the rest of a fold expression.
pub fn foldBlock(comptime Checker: type, b: collections.Builder(Checker), prepared: Source, statements: []const typed.StatementId, value: typed.NodeId) Error!typed.Node {
    var joined: std.ArrayList(typed.StatementId) = .empty;
    try joined.appendSlice(b.checker.allocator, prepared.setup);
    try joined.appendSlice(b.checker.allocator, statements);
    return b.block(joined.items, value);
}

/// Guard the refreshed source. Live lists accept growth and remember the new
/// bound; a later shrink traps even when it returns to the entry length.
pub fn guard(comptime Checker: type, b: collections.Builder(Checker), prepared: Source, owner: typed.LocalId, limit: typed.LocalId) Error!typed.StatementId {
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.appendSlice(b.checker.allocator, prepared.refresh);
    if (!prepared.checking) return b.stmt(.{ .block = try statements.toOwnedSlice(b.checker.allocator) });
    const check = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) });
    if (prepared.growing) {
        const actual = try b.length(owner);
        try statements.append(b.checker.allocator, try b.stmt(.{ .branch = .{ .condition = try b.binary(.lt, actual, try b.read(limit), .bool), .then_body = check, .else_body = null } }));
        try statements.append(b.checker.allocator, try b.stmt(.{ .assign = .{ .slot = limit, .value = actual } }));
    } else try statements.append(b.checker.allocator, check);
    return b.stmt(.{ .block = try statements.toOwnedSlice(b.checker.allocator) });
}

fn entry(comptime Checker: type, b: collections.Builder(Checker), owner: typed.LocalId, input: typed.NodeId, checking: bool) Error!Source {
    return .{ .setup = try b.checker.allocator.dupe(typed.StatementId, &.{try b.stmt(.{ .initialize = .{ .slot = owner, .value = input } })}), .checking = checking };
}

fn initializer(comptime Checker: type, checker: *Checker, slot: typed.LocalId) ?typed.NodeId {
    if (!checker.locals.items[@backingInt(slot)].usage.temporary) return null;
    // Statement IDs are program-wide, while local IDs restart in each
    // function. Search only the current function, newest initializer first.
    var at = checker.statements.items.len;
    while (at > checker.function_statement_start) {
        at -= 1;
        const statement = checker.statements.items[at];
        if (statement.data == .initialize and statement.data.initialize.slot == slot) return statement.data.initialize.value;
    }
    return null;
}

fn rootOf(comptime Checker: type, checker: *Checker, input: typed.NodeId, depth: usize) ?typed.LocalId {
    if (depth == 64) return null;
    return switch (checker.nodes.items[@backingInt(input)].data) {
        .local => |slot| if (initializer(Checker, checker, slot)) |value| rootOf(Checker, checker, value, depth + 1) else if (!checker.locals.items[@backingInt(slot)].usage.temporary) slot else null,
        .field => |field| blk: {
            if (projected(Checker, checker, field.base, field.index)) |value| break :blk rootOf(Checker, checker, value, depth + 1);
            break :blk rootOf(Checker, checker, field.base, depth + 1);
        },
        .index => |index| rootOf(Checker, checker, index.base, depth + 1),
        .block_value => |block| rootOf(Checker, checker, block.value, depth + 1),
        .buffer_operation => |op| if (op.kind == .read and op.arguments.len == 1) if (initializer(Checker, checker, op.owner)) |value| rootOf(Checker, checker, value, depth + 1) else null else null,
        else => null,
    };
}

fn projected(comptime Checker: type, checker: *Checker, input: typed.NodeId, index: usize) ?typed.NodeId {
    var value = input;
    for (0..64) |_| {
        const node = checker.nodes.items[@backingInt(value)];
        if (node.data == .block_value) {
            const body = checker.statements.items[@backingInt(node.data.block_value.body)];
            if (body.data != .block or body.data.block.len != 0) return null;
            value = node.data.block_value.value;
        } else if (node.data == .record) {
            for (node.data.record) |field| if (field.index == index) return field.value;
            return null;
        } else return null;
    }
    return null;
}

fn changes(comptime Checker: type, checker: *Checker, body: ast.StatementId, name: []const u8) Error!bool {
    const syntax: loop_rebinding.Syntax = .{ .program = checker.syntax, .src = checker.src };
    if (try loop_rebinding.assigns(checker.allocator, syntax, body, name)) return true;
    const span = checker.syntax.statements.items[@backingInt(body)].span;
    for (checker.syntax.nodes.items) |node| {
        if (node.span.start < span.start or node.span.end > span.end) continue;
        const target: ?ast.NodeId = switch (node.data) {
            .mut_argument => |value| value,
            .list_operation => |op| if (writes(op.kind)) op.base else null,
            .method_call => |call| if (methodChanges(Checker, checker, call.base, call.name)) call.base else null,
            .call => |call| if (call.owner) |owner| blk: {
                if (!std.mem.eql(u8, checker.src.text(owner), name)) break :blk null;
                const slot = checker.active.get(name) orelse break :blk null;
                if (receiverChanges(Checker, checker, checker.locals.items[@backingInt(slot)].ty, call.name)) return true;
                break :blk null;
            } else null,
            .buffer_operation => |op| if (writes(op.kind) and std.mem.eql(u8, checker.src.text(op.owner), name)) return true else null,
            else => null,
        };
        if (target) |value| if (loop_rebinding.rootedAt(syntax, value, name)) return true;
    }
    return false;
}

fn methodChanges(comptime Checker: type, checker: *Checker, base: ast.NodeId, name: source.Span) bool {
    const resolved = checker.resolved[@backingInt(base)] orelse return true;
    return receiverChanges(Checker, checker, checker.nodes.items[@backingInt(resolved)].ty, name);
}

fn receiverChanges(comptime Checker: type, checker: *Checker, ty: typed.Type, name: source.Span) bool {
    if (!ty.isAggregate() or !checker.catalog.records[ty.recordIndex()].isCollection()) return true;
    const kind = operations.method(checker.src.text(name)) orelse return true;
    return writes(kind);
}

fn writes(kind: operations.Kind) bool {
    return kind.writesReceiver() or kind == .set_add or kind == .set_discard;
}

fn Path(comptime Checker: type) type {
    return struct {
        b: collections.Builder(Checker),
        setup: std.ArrayList(typed.StatementId) = .empty,
        refresh: std.ArrayList(typed.StatementId) = .empty,

        fn rebuild(self: *@This(), input: typed.NodeId, depth: usize) Error!typed.NodeId {
            if (depth == 64) return error.InternalError;
            const b = self.b;
            const node = b.checker.nodes.items[@backingInt(input)];
            return switch (node.data) {
                .local => |slot| if (initializer(Checker, b.checker, slot)) |value| self.rebuild(value, depth + 1) else b.read(slot),
                // Managed indexing's block roots its base; element() rebuilds
                // that initializer. Index-expression blocks remain in spill()
                // so their side effects and negative-index normalization run
                // once, after the rebuilt base has been initialized.
                .block_value => |block| self.rebuild(block.value, depth + 1),
                .field => |field| blk: {
                    if (projected(Checker, b.checker, field.base, field.index)) |value| break :blk try self.rebuild(value, depth + 1);
                    break :blk try b.node(node.ty, .{ .field = .{ .base = try self.rebuild(field.base, depth + 1), .index = field.index } });
                },
                .index => |index| blk: {
                    const base = try self.rebuild(index.base, depth + 1);
                    const ty = b.checker.nodes.items[@backingInt(base)].ty;
                    if (b.checker.catalog.records[ty.recordIndex()].isCollection()) {
                        const owner = try b.local(ty);
                        break :blk try self.ancestor(owner, base, index.index);
                    }
                    const at = try self.spill(index.index);
                    break :blk try b.node(node.ty, .{ .index = .{ .base = base, .index = at, .from_end = index.from_end } });
                },
                .buffer_operation => |op| try self.element(op.owner, op.arguments[0], depth),
                else => error.InternalError,
            };
        }

        fn spill(self: *@This(), input: typed.NodeId) Error!typed.NodeId {
            const b = self.b;
            const slot = try b.local(b.checker.nodes.items[@backingInt(input)].ty);
            try self.setup.append(b.checker.allocator, try b.stmt(.{ .initialize = .{ .slot = slot, .value = input } }));
            return b.read(slot);
        }

        fn element(self: *@This(), owner: typed.LocalId, index: typed.NodeId, depth: usize) Error!typed.NodeId {
            const b = self.b;
            const base = initializer(Checker, b.checker, owner) orelse return error.InternalError;
            const value = try self.rebuild(base, depth + 1);
            return self.ancestor(owner, value, index);
        }

        fn ancestor(self: *@This(), owner: typed.LocalId, value: typed.NodeId, index: typed.NodeId) Error!typed.NodeId {
            const b = self.b;
            try self.setup.append(b.checker.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = value } }));
            try self.refresh.append(b.checker.allocator, try b.stmt(.{ .assign = .{ .slot = owner, .value = value } }));
            const length = try b.local(.i64);
            try self.setup.append(b.checker.allocator, try b.stmt(.{ .initialize = .{ .slot = length, .value = try b.length(owner) } }));
            try self.refresh.append(b.checker.allocator, try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(length)}) }));
            return b.operation(owner, .read, &.{try self.spill(index)});
        }
    };
}

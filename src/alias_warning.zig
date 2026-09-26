//! Advisory migration analysis for code that still relies on shared values.
//!
//! The pass runs on the checked program, with the value-semantics switch off.
//! It records a source-to-destination transfer and only warns when a later
//! write to one home can be observed through the other. It uses the same
//! managed-value and path facts as value-semantics lowering. The warning is
//! advisory because class graphs and indirect calls can require a human
//! migration rather than a source edit.
const std = @import("std");
const typed = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const values = @import("value_semantics.zig");
const value_checks = @import("value_semantics_check.zig");
const mutation = @import("mutation.zig");

pub const code = "W_ALIAS_DEPENDENT";
const Category = enum { local_alias, class_graph, store, across_call };
const Transfer = struct {
    span: source.Span,
    src: typed.LocalId,
    dst: typed.LocalId,
    category: Category,
    retained: bool = false,
    nested: bool = false,
    mut_call: bool = false,
};
const Access = struct { span: source.Span, root: typed.LocalId, write: bool, sync_from: ?typed.LocalId = null, matched: ?source.Span = null, returned: bool = false };
const ClassIndex = struct {
    reachable: []bool,

    fn init(a: std.mem.Allocator, records: []const typed.Record) !ClassIndex {
        const reachable = try a.alloc(bool, records.len);
        errdefer a.free(reachable);
        @memset(reachable, false);
        const parents = try a.alloc(std.ArrayList(usize), records.len);
        errdefer a.free(parents);
        @memset(parents, .empty);
        const queue = try a.alloc(usize, records.len);
        errdefer a.free(queue);
        var tail: usize = 0;
        for (records, 0..) |record, parent| {
            if (record.isManagedRecord()) {
                reachable[parent] = true;
                queue[tail] = parent;
                tail += 1;
            }
            if (record.isCollection()) {
                if (record.shape.buffer) |child| try addParent(a, parents, child, parent);
                continue;
            }
            if (record.shape.array) |array| try addParent(a, parents, array.element, parent);
            if (record.shape.variants) |variants| for (variants.cases) |case| {
                if (case.payload) |payload| try addParent(a, parents, payload, parent);
            };
            for (record.fields) |field| try addParent(a, parents, field.ty, parent);
        }
        var head: usize = 0;
        while (head < tail) : (head += 1) {
            for (parents[queue[head]].items) |parent| {
                if (reachable[parent]) continue;
                reachable[parent] = true;
                queue[tail] = parent;
                tail += 1;
            }
        }
        return .{ .reachable = reachable };
    }

    fn addParent(a: std.mem.Allocator, parents: []std.ArrayList(usize), child: typed.Type, parent: usize) !void {
        if (!child.isAggregate()) return;
        const index = child.recordIndex();
        if (index < parents.len) try parents[index].append(a, parent);
    }

    fn contains(self: ClassIndex, ty: typed.Type) bool {
        return ty.isAggregate() and ty.recordIndex() < self.reachable.len and self.reachable[ty.recordIndex()];
    }
};
const Reachability = struct {
    transfers: []const Transfer,
    seen: []u32,
    queue: []typed.LocalId,
    generation: u32 = 0,

    fn contains(self: *Reachability, origin: typed.LocalId, target: typed.LocalId) bool {
        if (origin == target) return true;
        self.generation +%= 1;
        if (self.generation == 0) {
            @memset(self.seen, 0);
            self.generation = 1;
        }
        var head: usize = 0;
        var tail: usize = 1;
        self.queue[0] = origin;
        self.seen[@backingInt(origin)] = self.generation;
        while (head < tail) : (head += 1) {
            const current = self.queue[head];
            for (self.transfers) |transfer| {
                if (transfer.src != current or transfer.dst == current) continue;
                if (transfer.dst == target) return true;
                const next = @backingInt(transfer.dst);
                if (self.seen[next] == self.generation) continue;
                self.seen[next] = self.generation;
                self.queue[tail] = transfer.dst;
                tail += 1;
            }
        }
        return false;
    }
};
const Bindings = struct { roots: []?typed.LocalId, sites: []?source.Span };
const Events = struct { transfers: *std.ArrayList(Transfer), accesses: *std.ArrayList(Access) };
const Context = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    function: typed.Function,
    facts: *const values.Facts,
    classes: ClassIndex,
    bindings: Bindings,
    events: Events,
};

/// Add advisory warnings for transfer sites that have an observed write/read
/// divergence. A switch-on check reports the value errors instead.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: typed.Program, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    if (values.enabled()) return;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const classes = try ClassIndex.init(a, program.records);
    for (program.functions) |function| {
        if (function.policy.host != null) continue;
        const facts = try values.Facts.collect(a, program, function);
        var transfers: std.ArrayList(Transfer) = .empty;
        var accesses: std.ArrayList(Access) = .empty;
        const bindings = try a.alloc(?typed.LocalId, function.scope.locals.len);
        @memset(bindings, null);
        const binding_sites = try a.alloc(?source.Span, function.scope.locals.len);
        @memset(binding_sites, null);
        const ctx: Context = .{
            .allocator = a,
            .program = program,
            .function = function,
            .facts = &facts,
            .classes = classes,
            .bindings = .{ .roots = bindings, .sites = binding_sites },
            .events = .{ .transfers = &transfers, .accesses = &accesses },
        };
        var walker = try typed_walk.Walker.init(a, program, function.scope.body);
        while (try walker.next()) |item| switch (item) {
            .statement => |id| try statement(ctx, id),
            .expression => |id| try expression(ctx, id),
        };
        var reach: Reachability = .{
            .transfers = transfers.items,
            .seen = try a.alloc(u32, function.scope.locals.len),
            .queue = try a.alloc(typed.LocalId, function.scope.locals.len),
        };
        @memset(reach.seen, 0);
        for (transfers.items, 0..) |transfer, index| {
            if (transfer.src == transfer.dst and transfer.category != .store and transfer.category != .class_graph) continue;
            const sides = try transferSides(a, function.scope.locals.len, transfers.items, index);
            const self_store = selfWrite(src, transfer, accesses.items);
            const repeated = duplicateStore(src, transfers.items, accesses.items, index, &reach);
            const sibling = siblingDiverges(transfer, transfers.items, accesses.items);
            const cycle = reciprocalStore(transfer, transfers.items);
            const evidenced = self_store or repeated or sibling or cycle;
            if (!evidenced) {
                if (!diverges(function, transfer, sides, accesses.items, &reach)) continue;
            }
            if (alreadyReported(program, sink, transfer.span)) continue;
            const fix = try storeBackFix(allocator, src, function, transfer, accesses.items);
            try sink.items.append(allocator, .{
                .code = code,
                .severity = .warning,
                .span = transfer.span,
                .message = message(transfer.category),
                .provenance = .{ .fix = fix },
            });
        }
        // A `for` or match binding and a direct write to a function result
        // have no ordinary named assignment site. Reuse the switch's checked
        // write witnesses, but render them as migration warnings here.
        var candidates: diagnostic.Sink = .{ .allocator = a };
        _ = try value_checks.checkWrites(a, program, @backingInt(function.id), &candidates);
        for (candidates.items.items) |candidate| {
            if (alreadyReported(program, sink, candidate.span)) continue;
            if (plainRecordRead(program, candidate.span)) continue;
            const category: Category = if (std.mem.eql(u8, candidate.code, value_checks.temporary_write_code)) .across_call else .local_alias;
            try sink.items.append(allocator, .{ .code = code, .severity = .warning, .span = candidate.span, .message = message(category) });
        }
        for (accesses.items) |access| {
            if (!access.write or @backingInt(access.root) >= function.signature.parameter_count) continue;
            const binding = access.matched orelse continue;
            if (alreadyReported(program, sink, binding)) continue;
            const ty = function.scope.locals[@backingInt(access.root)].ty;
            const category: Category = if (classes.contains(ty)) .class_graph else .local_alias;
            try sink.items.append(allocator, .{ .code = code, .severity = .warning, .span = binding, .message = message(category) });
        }
    }
}

fn plainRecordRead(program: typed.Program, span: source.Span) bool {
    for (program.nodes) |node| {
        if (node.span.start != span.start or node.span.end != span.end) continue;
        if (!node.ty.isAggregate()) continue;
        const record = program.records[node.ty.recordIndex()];
        const plain = record.isRecord() and !record.managed;
        if (plain and !typed.carriesWritableStorage(program.records, node.ty)) return true;
    }
    return false;
}

fn duplicateStore(src: source.Source, transfers: []const Transfer, accesses: []const Access, omitted: usize, reach: *Reachability) bool {
    const transfer = transfers[omitted];
    if (transfer.category != .store and transfer.category != .class_graph) return false;
    const location = src.locate(transfer.span.start);
    for (transfers, 0..) |other, index| {
        if (index == omitted or other.category != transfer.category) continue;
        if (other.src != transfer.src or other.dst != transfer.dst) continue;
        const peer = src.locate(other.span.start);
        if (!std.mem.eql(u8, peer.path, location.path) or peer.line != location.line) continue;
        for (accesses) |write| {
            if (!write.write or write.span.start < transfer.span.end) continue;
            if (!reach.contains(transfer.dst, write.root)) continue;
            for (accesses) |read| {
                if (read.write or read.span.start < write.span.end) continue;
                if (read.root == write.root and transfer.category != .class_graph) continue;
                if (reach.contains(transfer.dst, read.root)) return true;
            }
        }
    }
    return false;
}

fn selfWrite(src: source.Source, transfer: Transfer, accesses: []const Access) bool {
    if (transfer.src != transfer.dst) return false;
    const site = src.locate(transfer.span.start);
    for (accesses) |access| {
        if (!access.write or access.root != transfer.src) continue;
        const location = src.locate(access.span.start);
        if (std.mem.eql(u8, location.path, site.path) and location.line == site.line) return true;
    }
    return false;
}

fn reciprocalStore(transfer: Transfer, transfers: []const Transfer) bool {
    if (transfer.category != .store and transfer.category != .class_graph) return false;
    for (transfers) |other| {
        if (other.category != .store and other.category != .class_graph) continue;
        if (other.src == transfer.dst and other.dst == transfer.src and other.span.start > transfer.span.start) return true;
    }
    return false;
}

fn siblingDiverges(transfer: Transfer, transfers: []const Transfer, accesses: []const Access) bool {
    if (transfer.category != .local_alias) return false;
    for (transfers) |other| {
        if (other.src != transfer.src or other.dst == transfer.dst) continue;
        const after = @max(transfer.span.end, other.span.end);
        for (accesses) |write| {
            if (!write.write or write.root != other.dst or write.span.start < after) continue;
            for (accesses) |read| {
                if (read.write or read.root != transfer.dst or read.span.start <= write.span.end) continue;
                return true;
            }
        }
    }
    return false;
}

fn message(category: Category) []const u8 {
    return switch (category) {
        .local_alias => "local alias: this shared collection is written after another name takes it; value semantics gives each name an independent value",
        .class_graph => "class graph: this transfer relies on shared object identity; migrate the graph to explicit ownership or an object table before retiring class",
        .store => "store: this value is held in another collection, field or payload and later written through a different path; store the updated value back",
        .across_call => "across a call: a returned or retained argument is later written through another path; return and store back the updated value or use a mut parameter",
    };
}

fn alreadyReported(program: typed.Program, sink: *diagnostic.Sink, span: source.Span) bool {
    _ = program;
    for (sink.items.items) |item| {
        if (std.mem.eql(u8, item.code, code) and item.span.start == span.start) return true;
    }
    return false;
}

/// Legacy alias edges other than the transfer being tested divide names into
/// the transfer's source and destination sides. A later copy severs only the
/// tested edge, so another alias of either side remains observable.
fn transferSides(a: std.mem.Allocator, locals: usize, transfers: []const Transfer, omitted: usize) ![]u2 {
    const sides = try a.alloc(u2, locals);
    @memset(sides, 0);
    sides[@backingInt(transfers[omitted].src)] = 1;
    sides[@backingInt(transfers[omitted].dst)] = 2;
    var changed = true;
    while (changed) {
        changed = false;
        for (transfers, 0..) |other, index| {
            if (index == omitted) continue;
            const src = @backingInt(other.src);
            const dst = @backingInt(other.dst);
            const unioned = sides[src] | sides[dst];
            if (sides[src] != unioned or sides[dst] != unioned) {
                sides[src] = unioned;
                sides[dst] = unioned;
                changed = true;
            }
        }
    }
    return sides;
}

fn diverges(function: typed.Function, transfer: Transfer, sides: []const u2, accesses: []const Access, reach: *Reachability) bool {
    if (transfer.nested and @backingInt(transfer.src) < function.signature.parameter_count) {
        var writes_result = false;
        for (accesses) |access| {
            if (!access.write or access.span.start < transfer.span.end) continue;
            if (reach.contains(transfer.dst, access.root)) writes_result = true;
        }
        if (!writes_result and !transfer.mut_call) return false;
    }
    if (transfer.retained) {
        for (accesses) |access| {
            if (access.write and access.span.start > transfer.span.end and (sides[@backingInt(access.root)] & 1) != 0) return true;
        }
    }
    if (transfer.category == .store and @backingInt(transfer.src) < function.signature.parameter_count) {
        for (accesses) |access| if (access.returned and access.root == transfer.dst and access.span.start >= transfer.span.end) return true;
    }
    if (directDiverges(function, transfer, accesses)) return true;
    for (accesses) |write| {
        if (!write.write or write.span.start < transfer.span.end) continue;
        const write_side = sides[@backingInt(write.root)];
        if (write_side == 0) continue;
        for (0..function.signature.parameter_count) |parameter| {
            const read_side = sides[parameter];
            if (!opposite(write_side, read_side)) continue;
            const other: typed.LocalId = @fromBackingInt(@intCast(parameter));
            if (!synced(accesses, other, write.root, write.span.end, std.math.maxInt(usize))) return true;
        }
        for (accesses) |read| {
            if (read.write or read.sync_from != null or read.span.start < write.span.end) continue;
            if (!opposite(write_side, sides[@backingInt(read.root)])) continue;
            if (syncContains(accesses, read.root, write.root, read.span)) continue;
            if (synced(accesses, read.root, write.root, write.span.end, read.span.start)) continue;
            return true;
        }
    }
    return false;
}

fn directDiverges(function: typed.Function, transfer: Transfer, accesses: []const Access) bool {
    for (accesses) |write| {
        if (!write.write or write.span.start < transfer.span.end) continue;
        const other = if (write.root == transfer.dst) transfer.src else if (write.root == transfer.src) transfer.dst else continue;
        if (@backingInt(other) < function.signature.parameter_count and !synced(accesses, other, write.root, write.span.end, std.math.maxInt(usize))) return true;
        for (accesses) |read| {
            if (read.write or read.sync_from != null or read.root != other or read.span.start < write.span.end) continue;
            if (syncContains(accesses, other, write.root, read.span)) continue;
            if (synced(accesses, other, write.root, write.span.end, read.span.start)) continue;
            return true;
        }
    }
    return false;
}

fn opposite(write: u2, read: u2) bool {
    return (write == 1 and read == 2) or (write == 2 and read == 1);
}

fn synced(accesses: []const Access, target: typed.LocalId, from: typed.LocalId, after: usize, before: usize) bool {
    for (accesses) |access| {
        if (access.sync_from != from or access.root != target) continue;
        if (access.span.start >= after and access.span.end <= before) return true;
    }
    return false;
}

fn syncContains(accesses: []const Access, target: typed.LocalId, from: typed.LocalId, span: source.Span) bool {
    for (accesses) |access| {
        if (access.sync_from != from or access.root != target) continue;
        if (span.start >= access.span.start and span.end <= access.span.end) return true;
    }
    return false;
}

/// Attach a one-step repair only when the copy is between two mutable named
/// locals and the first divergent write occupies a standalone source line.
/// Rechecking after the insertion can publish the next repair in a loop.
fn storeBackFix(allocator: std.mem.Allocator, src: source.Source, function: typed.Function, transfer: Transfer, accesses: []const Access) !?diagnostic.Fix {
    if (transfer.category != .local_alias) return null;
    const first = function.scope.locals[@backingInt(transfer.src)];
    const second = function.scope.locals[@backingInt(transfer.dst)];
    if (first.ty != second.ty) return null;
    if (!first.mutable or !second.mutable) return null;
    if (!values.namedHome(function, @backingInt(transfer.src))) return null;
    if (!values.namedHome(function, @backingInt(transfer.dst))) return null;
    for (accesses) |write| {
        if (!write.write or write.span.start < transfer.span.end) continue;
        const other = if (write.root == transfer.dst) transfer.src else if (write.root == transfer.src) transfer.dst else continue;
        if (synced(accesses, other, write.root, write.span.end, std.math.maxInt(usize))) continue;
        const to = function.scope.locals[@backingInt(other)];
        const from = function.scope.locals[@backingInt(write.root)];
        if (@backingInt(other) < function.signature.parameter_count) {
            var declared = false;
            for (function.signature.declared_mutates) |position| if (position == @backingInt(other)) {
                declared = true;
            };
            if (!declared) return null;
        }
        if (write.span.end > src.bytes.len) return null;
        const end = std.mem.indexOfScalarPos(u8, src.bytes, write.span.end, '\n') orelse src.bytes.len;
        const start = if (std.mem.lastIndexOfScalar(u8, src.bytes[0..write.span.start], '\n')) |at| at + 1 else 0;
        const line = src.bytes[start..end];
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (!standaloneWrite(trimmed)) return null;
        const indent = line[0 .. line.len - trimmed.len];
        const replacement = try std.fmt.allocPrint(allocator, "\n{s}{s} = {s}", .{ indent, to.name, from.name });
        return .{ .edit = .{ .span = .{ .start = end, .end = end }, .text = replacement } };
    }
    return null;
}

fn standaloneWrite(line: []const u8) bool {
    if (line.len == 0) return false;
    for ([_][]const u8{ "return ", "if ", "while ", "for ", "case ", "match ", "assert ", "with " }) |header| {
        if (std.mem.startsWith(u8, line, header)) return false;
    }
    return true;
}

fn addAccess(allocator: std.mem.Allocator, accesses: *std.ArrayList(Access), root: ?typed.LocalId, span: source.Span, write: bool) !void {
    if (root) |slot| try accesses.append(allocator, .{ .span = span, .root = slot, .write = write });
}

fn addTransfer(ctx: Context, value: typed.NodeId, target: typed.LocalId, span: source.Span, category: Category) !void {
    const ty = ctx.program.nodes[@backingInt(value)].ty;
    if (category != .across_call and freshConstruction(ctx, value, 0)) return;
    const byte_buffer = ty.isAggregate() and std.mem.eql(u8, ctx.program.records[ty.recordIndex()].name, "byte_buffer");
    if (byte_buffer and category == .local_alias) {
        if (valueRoot(ctx, value)) |origin| {
            if (ctx.function.scope.locals[@backingInt(origin)].ty != ty) return;
        }
    }
    const live_view = values.isLiveView(ctx.program.records, ty);
    const view_result = switch (ctx.program.nodes[@backingInt(value)].data) {
        .buffer_operation => |operation| operation.kind == .values or operation.kind == .keys or operation.kind == .items,
        else => false,
    };
    const carries_alias = values.needsCopy(ctx.program.records, ty) or ctx.classes.contains(ty);
    const is_view = live_view or view_result;
    if (!carries_alias and !is_view) return;
    const wraps_alias = switch (ctx.program.nodes[@backingInt(value)].data) {
        .variant => |variant| if (variant.value) |child| valueRoot(ctx, child) != null else false,
        .wrap => |child| valueRoot(ctx, child) != null,
        .arena_escape => |child| valueRoot(ctx, child) != null,
        else => false,
    };
    const transfer_is_fresh = ctx.facts.classify(value, target) == .fresh;
    if (category != .across_call) {
        const may_share = is_view or wraps_alias;
        if (!may_share and transfer_is_fresh) return;
    }
    const root = valueRoot(ctx, value) orelse return;
    const final_category: Category = if (ctx.classes.contains(ty)) .class_graph else category;
    const nested = ctx.program.nodes[@backingInt(value)].data != .local;
    try ctx.events.transfers.append(ctx.allocator, .{ .span = span, .src = root, .dst = target, .category = final_category, .nested = nested, .mut_call = mutableCallBorrow(ctx, value) });
}

fn mutableCallBorrow(ctx: Context, id: typed.NodeId) bool {
    const node = ctx.program.nodes[@backingInt(id)];
    return switch (node.data) {
        .field => |field| mutableCallBorrow(ctx, field.base),
        .block_value => |block| mutableCallBorrow(ctx, block.value),
        .call => |call| ctx.program.functions[@backingInt(call.function)].signature.declared_mutates.len != 0,
        else => false,
    };
}

fn freshConstruction(ctx: Context, id: typed.NodeId, depth: usize) bool {
    if (depth == 16) return false;
    const node = ctx.program.nodes[@backingInt(id)];
    return switch (node.data) {
        .acquire_buffer => true,
        .block_value => |block| freshConstruction(ctx, block.value, depth + 1),
        .local => |slot| blk: {
            const index = @backingInt(slot);
            if (!ctx.facts.synthetic[index]) break :blk false;
            const stored = ctx.facts.stores[index] orelse break :blk false;
            break :blk freshConstruction(ctx, stored, depth + 1);
        },
        else => false,
    };
}

/// A returned view or record can originate in a parameter even when the
/// immediate field or pattern access looks like a fresh expression.
fn callBorrow(ctx: Context, id: typed.NodeId) bool {
    const node = ctx.program.nodes[@backingInt(id)];
    return switch (node.data) {
        .field => |field| callBorrow(ctx, field.base),
        .block_value => |block| callBorrow(ctx, block.value),
        .cast, .wrap, .unwrap => |value| callBorrow(ctx, value),
        .call => |call| {
            const origin = ctx.program.functions[@backingInt(call.function)].signature.return_origin;
            const byte_buffer = node.ty.isAggregate() and std.mem.eql(u8, ctx.program.records[node.ty.recordIndex()].name, "byte_buffer");
            return switch (origin) {
                .params => |positions| for (positions) |position| {
                    if (position >= call.arguments.len) continue;
                    const argument = ctx.program.nodes[@backingInt(call.arguments[position])];
                    if (!byte_buffer or argument.ty == node.ty) break true;
                } else false,
                else => false,
            };
        },
        else => false,
    };
}

fn valueRoot(ctx: Context, id: typed.NodeId) ?typed.LocalId {
    const node = ctx.program.nodes[@backingInt(id)];
    switch (node.data) {
        .field => |field| return valueRoot(ctx, field.base),
        .index => |access| return valueRoot(ctx, access.base),
        .block_value => |block| return valueRoot(ctx, block.value),
        .arena_escape, .cast, .unwrap, .wrap => |value| return valueRoot(ctx, value),
        .variant => |variant| return if (variant.value) |value| valueRoot(ctx, value) else null,
        .record => |fields| if (values.isLiveView(ctx.program.records, node.ty) and fields.len == 1) return valueRoot(ctx, fields[0].value),
        .buffer_operation => |operation| switch (operation.kind) {
            .read, .get, .key_at, .value_at, .keys, .values, .items => return localRoot(ctx, operation.owner),
            else => {},
        },
        .call => |call| {
            const callee = ctx.program.functions[@backingInt(call.function)];
            const position = switch (callee.signature.return_origin) {
                .params => |positions| if (positions.len == 1) positions[0] else return null,
                .unknown => unknownReturnArgument(ctx, call.arguments) orelse return null,
                .fresh => return null,
            };
            if (position >= call.arguments.len) return null;
            return valueRoot(ctx, call.arguments[position]);
        },
        else => {},
    }
    const slot = values.pathRoot(ctx.program, id) orelse return null;
    return localRoot(ctx, slot);
}

fn unknownReturnArgument(ctx: Context, arguments: []const typed.NodeId) ?u16 {
    var found: ?u16 = null;
    for (arguments, 0..) |argument, position| {
        const ty = ctx.program.nodes[@backingInt(argument)].ty;
        if (!values.needsCopy(ctx.program.records, ty) and !ctx.classes.contains(ty)) continue;
        if (found != null) return null;
        found = @intCast(position);
    }
    return found;
}

/// Follow both ordinary compiler temporaries and a match arm's hidden payload
/// binding back to the source name the programmer can observe.
fn localRoot(ctx: Context, start: typed.LocalId) typed.LocalId {
    var slot = start;
    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        const index = @backingInt(slot);
        if (ctx.bindings.roots[index]) |bound| {
            slot = bound;
            continue;
        }
        if (!ctx.facts.synthetic[index]) return slot;
        const stored = ctx.facts.stores[index] orelse return slot;
        slot = values.pathRoot(ctx.program, stored) orelse return slot;
    }
    return slot;
}

fn matchSite(ctx: Context, start: typed.LocalId) ?source.Span {
    var slot = start;
    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        const index = @backingInt(slot);
        if (ctx.bindings.sites[index]) |site| return site;
        if (!ctx.facts.synthetic[index]) return null;
        const stored = ctx.facts.stores[index] orelse return null;
        slot = values.pathRoot(ctx.program, stored) orelse return null;
    }
    return null;
}

fn statement(ctx: Context, id: typed.StatementId) !void {
    const stmt = ctx.program.statements[@backingInt(id)];
    switch (stmt.data) {
        .ret => |value| if (valueRoot(ctx, value)) |root| {
            try ctx.events.accesses.append(ctx.allocator, .{ .span = stmt.span, .root = root, .write = false, .returned = true });
        },
        .initialize, .assign => |store| {
            // A collection literal is lowered through a synthetic local and
            // a block value. Its element stores happen before the named
            // initialize, so relate that temporary to the eventual home.
            const stored_node = ctx.program.nodes[@backingInt(store.value)];
            const fresh = ctx.facts.classify(store.value, store.slot) == .fresh;
            if (fresh or stored_node.data == .block_value) {
                if (valueRoot(ctx, store.value)) |root| {
                    if (ctx.facts.synthetic[@backingInt(root)]) ctx.bindings.roots[@backingInt(root)] = store.slot;
                }
            }
            if (stmt.data == .assign) if (valueRoot(ctx, store.value)) |origin| {
                try ctx.events.accesses.append(ctx.allocator, .{ .span = stmt.span, .root = store.slot, .write = false, .sync_from = origin });
            };
            if (ctx.facts.namedStore(store.slot)) {
                const category: Category = if (callBorrow(ctx, store.value)) .across_call else .local_alias;
                const local = ctx.function.scope.locals[@backingInt(store.slot)];
                const span = if (local.origin == .iteration) local.declaration else stmt.span;
                try addTransfer(ctx, store.value, store.slot, span, category);
                // A record, array or wrapper keeps each transferred component
                // even when the outer value itself was just constructed.
                try storedChildren(ctx, store.value, store.slot);
            }
            const value = ctx.program.nodes[@backingInt(store.value)];
            if (value.data == .update or value.data == .replace) {
                const base = switch (value.data) {
                    .update => |update| update.base,
                    .replace => |replace| replace.base,
                    else => unreachable,
                };
                const root = values.pathRoot(ctx.program, base) orelse store.slot;
                try ctx.events.accesses.append(ctx.allocator, .{ .span = stmt.span, .root = localRoot(ctx, store.slot), .write = true, .matched = matchSite(ctx, root) });
                try storedChildren(ctx, store.value, store.slot);
            }
        },
        .match => |matched| for (matched.arms) |arm| if (arm.slot) |slot| {
            const borrowed_call = callBorrow(ctx, matched.value);
            if (!borrowed_call) ctx.bindings.roots[@backingInt(slot)] = valueRoot(ctx, matched.value);
            const span = ctx.function.scope.locals[@backingInt(slot)].declaration;
            ctx.bindings.sites[@backingInt(slot)] = span;
            const category: Category = if (borrowed_call) .across_call else .local_alias;
            const site = if (category == .across_call) ctx.program.nodes[@backingInt(matched.value)].span else stmt.span;
            try addTransfer(ctx, matched.value, slot, site, category);
        },
        else => {},
    }
}

fn storedChildren(ctx: Context, id: typed.NodeId, target: typed.LocalId) !void {
    const node = ctx.program.nodes[@backingInt(id)];
    switch (node.data) {
        .local => |slot| {
            if (ctx.facts.synthetic[@backingInt(slot)]) {
                for (ctx.events.transfers.items) |transfer| if (transfer.dst == slot) {
                    try ctx.events.transfers.append(ctx.allocator, .{ .span = node.span, .src = transfer.src, .dst = target, .category = transfer.category });
                };
            }
        },
        .record => |fields| for (fields) |field| {
            try addTransfer(ctx, field.value, target, ctx.program.nodes[@backingInt(field.value)].span, .store);
            try storedChildren(ctx, field.value, target);
        },
        .array => |elements| for (elements) |element| {
            try addTransfer(ctx, element, target, ctx.program.nodes[@backingInt(element)].span, .store);
            try storedChildren(ctx, element, target);
        },
        .variant => |variant| if (variant.value) |value| {
            try addTransfer(ctx, value, target, ctx.program.nodes[@backingInt(value)].span, .store);
            try storedChildren(ctx, value, target);
        },
        .wrap => |value| {
            try addTransfer(ctx, value, target, ctx.program.nodes[@backingInt(value)].span, .store);
            try storedChildren(ctx, value, target);
        },
        .arena_escape => |value| try storedChildren(ctx, value, target),
        .block_value => |block| {
            if (valueRoot(ctx, block.value)) |temporary| {
                if (ctx.facts.synthetic[@backingInt(temporary)]) ctx.bindings.roots[@backingInt(temporary)] = target;
                for (ctx.events.transfers.items) |transfer| if (transfer.dst == temporary) {
                    try ctx.events.transfers.append(ctx.allocator, .{ .span = node.span, .src = transfer.src, .dst = target, .category = transfer.category });
                };
            }
        },
        .update => |update| for (update.fields) |field| {
            try addTransfer(ctx, field.value, target, ctx.program.nodes[@backingInt(field.value)].span, .store);
            try storedChildren(ctx, field.value, target);
        },
        else => {},
    }
}

/// A mutating call can keep a read-only argument inside the owner it writes.
/// Peel freshly built records and variants to find the existing homes being
/// handed over; the outer constructor itself has no alias root.
fn retainedLeaves(ctx: Context, id: typed.NodeId, target: typed.LocalId, span: source.Span) !void {
    const node = ctx.program.nodes[@backingInt(id)];
    switch (node.data) {
        .record => |fields| for (fields) |field| try retainedLeaves(ctx, field.value, target, span),
        .array => |elements| for (elements) |element| try retainedLeaves(ctx, element, target, span),
        .variant => |variant| if (variant.value) |value| try retainedLeaves(ctx, value, target, span),
        .wrap, .cast, .unwrap => |value| try retainedLeaves(ctx, value, target, span),
        .block_value => |block| try retainedLeaves(ctx, block.value, target, span),
        else => {
            const carries = values.needsCopy(ctx.program.records, node.ty) or ctx.classes.contains(node.ty);
            if (!carries) return;
            const root = valueRoot(ctx, id) orelse return;
            if (root == target) return;
            try ctx.events.transfers.append(ctx.allocator, .{ .span = span, .src = root, .dst = target, .category = .across_call, .retained = true });
        },
    }
}

fn constructedCarrier(ctx: Context, id: typed.NodeId) bool {
    const node = ctx.program.nodes[@backingInt(id)];
    return switch (node.data) {
        .record, .array, .variant, .wrap => true,
        .block_value => |block| constructedCarrier(ctx, block.value),
        else => false,
    };
}

fn callRetains(ctx: Context, arguments: []const typed.NodeId, mutates: []const u16, span: source.Span) !void {
    for (mutates) |position| {
        if (position >= arguments.len) continue;
        const owner = valueRoot(ctx, arguments[position]) orelse continue;
        try addAccess(ctx.allocator, ctx.events.accesses, owner, span, true);
        for (arguments, 0..) |argument, candidate| {
            if (candidate == position) continue;
            var also_mut = false;
            for (mutates) |declared| if (declared == candidate) {
                also_mut = true;
            };
            if (also_mut) continue;
            if (!constructedCarrier(ctx, argument)) continue;
            try retainedLeaves(ctx, argument, owner, span);
        }
    }
}

fn expression(ctx: Context, id: typed.NodeId) !void {
    const node = ctx.program.nodes[@backingInt(id)];
    switch (node.data) {
        .local => |slot| try addAccess(ctx.allocator, ctx.events.accesses, localRoot(ctx, slot), node.span, false),
        .buffer_operation => |operation| {
            if (operation.kind.mutates()) try ctx.events.accesses.append(ctx.allocator, .{ .span = node.span, .root = localRoot(ctx, operation.owner), .write = true, .matched = matchSite(ctx, operation.owner) });
            if (values.storedArgument(ctx.program.records, ctx.function.scope.locals[@backingInt(operation.owner)].ty, operation.kind)) |position| {
                if (position < operation.arguments.len) {
                    const value = operation.arguments[position];
                    try addTransfer(ctx, value, localRoot(ctx, operation.owner), node.span, .store);
                    try storedChildren(ctx, value, localRoot(ctx, operation.owner));
                }
            }
        },
        .call => |call| {
            const callee = ctx.program.functions[@backingInt(call.function)];
            try callRetains(ctx, call.arguments, callee.signature.declared_mutates, node.span);
        },
        else => {
            if (mutation.typedNode(ctx.program, ctx.function, node)) |witness| if (witness.operation == .receiver_write) {
                if (witness.owner) |owner| try ctx.events.accesses.append(ctx.allocator, .{ .span = witness.span, .root = localRoot(ctx, owner), .write = true, .matched = matchSite(ctx, owner) });
            };
        },
    }
}

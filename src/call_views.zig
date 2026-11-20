//! View classification from declared return signatures.
const std = @import("std");
const typed = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const return_borrow = @import("return_borrow.zig");

const InitCounts = struct { total: u32 = 0, views: u32 = 0, calls: u32 = 0, roots: ?[]const u32 = null };
const CallRoots = struct { roots: ?[]const u32 };

/// Mark immutable call-initialized text, bytes and list bindings as views only
/// when every initialization borrows the same complete set of local roots.
/// Source-declared view flags remain intact.
pub fn markCallViews(a: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error!void {
    for (@constCast(program.functions)) |*function| {
        if (function.policy.c_abi or function.policy.host != null) continue;
        var scratch = std.heap.ArenaAllocator.init(a);
        defer scratch.deinit();
        const temporary = scratch.allocator();
        var counts: std.AutoHashMapUnmanaged(u32, InitCounts) = .empty;
        var written: std.AutoHashMapUnmanaged(u32, void) = .empty;
        var walker = try typed_walk.Walker.init(temporary, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .statement => |id| {
                const data = program.statements[@backingInt(id)].data;
                if (data == .assign) try written.put(temporary, @intCast(@backingInt(data.assign.slot)), {});
                const store = switch (data) {
                    .initialize => |initialize| initialize,
                    else => continue,
                };
                const entry = try counts.getOrPut(temporary, @intCast(@backingInt(store.slot)));
                if (!entry.found_existing) entry.value_ptr.* = .{};
                const count = entry.value_ptr;
                count.total += 1;
                if (try callRoots(temporary, program, store.value)) |borrowed| {
                    count.calls += 1;
                    const roots = borrowed.roots orelse continue;
                    if (count.roots == null) count.roots = roots;
                    if (std.mem.eql(u32, count.roots.?, roots)) count.views += 1;
                } else if (sliceViewNode(program, store.value)) count.views += 1;
            },
            .expression => |id| try noteWrites(temporary, program, id, &written),
        };
        var it = counts.iterator();
        while (it.next()) |entry| {
            const count = entry.value_ptr.*;
            if (count.calls == 0 or count.views != count.total) continue;
            if (entry.key_ptr.* >= function.scope.locals.len) continue;
            const local = &@constCast(function.scope.locals)[entry.key_ptr.*];
            if (local.ownership.view or !viewType(program.records, local.ty)) continue;
            if (local.mutable and (!local.usage.temporary or written.contains(entry.key_ptr.*))) continue;
            local.ownership.view = true;
        }
    }
}

fn viewType(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (!record.isCollection()) return false;
    return switch (record.collection.kind) {
        .string, .bytes, .list => true,
        else => false,
    };
}

/// Record local write targets using declared mutation contracts only.
pub fn noteWrites(a: std.mem.Allocator, program: typed.Program, id: typed.NodeId, written: *std.AutoHashMapUnmanaged(u32, void)) std.mem.Allocator.Error!void {
    const node = program.nodes[@backingInt(id)];
    switch (node.data) {
        .buffer_operation => |operation| if (operation.kind.mutates()) try written.put(a, @intCast(@backingInt(operation.owner)), {}),
        .call => |call| {
            if (@backingInt(call.function) >= program.functions.len) return;
            const signature = program.functions[@backingInt(call.function)].signature;
            for (signature.declared_mutates) |position| {
                if (position >= call.arguments.len) continue;
                const argument = program.nodes[@backingInt(call.arguments[position])];
                if (argument.data == .local) try written.put(a, @intCast(@backingInt(argument.data.local)), {});
            }
        },
        else => {},
    }
}

/// Resolve every declared source of a view call. A nonlocal source prevents a
/// binding view, rather than dropping that source from its lifetime obligation.
fn callRoots(a: std.mem.Allocator, program: typed.Program, id: typed.NodeId) std.mem.Allocator.Error!?CallRoots {
    const node = program.nodes[@backingInt(id)];
    if (node.data == .block_value) return callRoots(a, program, node.data.block_value.value);
    if (node.data != .call) return null;
    const call = node.data.call;
    if (@backingInt(call.function) >= program.functions.len) return null;
    const signature = program.functions[@backingInt(call.function)].signature;
    switch (return_borrow.shape(program.records, signature).kind) {
        .text, .bytes, .list => {},
        else => return null,
    }
    var roots: std.ArrayList(u32) = .empty;
    errdefer roots.deinit(a);
    for (return_borrow.sources(signature)) |position| {
        if (position >= call.arguments.len) {
            roots.deinit(a);
            return .{ .roots = null };
        }
        const root = pathRoot(program, call.arguments[position]) orelse {
            roots.deinit(a);
            return .{ .roots = null };
        };
        if (std.mem.indexOfScalar(u32, roots.items, root) == null) try roots.append(a, root);
    }
    std.mem.sort(u32, roots.items, {}, std.sort.asc(u32));
    return .{ .roots = try roots.toOwnedSlice(a) };
}

fn pathRoot(program: typed.Program, id: typed.NodeId) ?u32 {
    const node = program.nodes[@backingInt(id)];
    return switch (node.data) {
        .local => |slot| @intCast(@backingInt(slot)),
        .field => |field| pathRoot(program, field.base),
        .index => |index| pathRoot(program, index.base),
        .cast, .wrap, .unwrap => |value| pathRoot(program, value),
        .block_value => |block| pathRoot(program, block.value),
        .buffer_operation => |operation| if (node.view) @intCast(@backingInt(operation.owner)) else null,
        else => null,
    };
}

fn sliceViewNode(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    return switch (node.data) {
        .buffer_operation => node.view,
        .block_value => |block| sliceViewNode(program, block.value),
        else => false,
    };
}

// O3: every declared owner, including high positions, participates in view classification.
test "declared call views retain all roots and list representation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const list: typed.Type = @fromBackingInt(typed.Type.record_base);
    const count = 130;
    const locals = try a.alloc(typed.Local, count + 1);
    const nodes = try a.alloc(typed.Node, count + 1);
    const arguments = try a.alloc(typed.NodeId, count);
    for (0..count) |position| {
        locals[position] = .{ .name = "input", .declaration = span, .ty = list, .mutable = false, .origin = .parameter };
        nodes[position] = .{ .span = span, .ty = list, .data = .{ .local = @fromBackingInt(position) } };
        arguments[position] = @fromBackingInt(position);
    }
    locals[count] = .{ .name = "selected", .declaration = span, .ty = list, .mutable = false, .origin = .local };
    nodes[count] = .{ .span = span, .ty = list, .data = .{ .call = .{ .function = @fromBackingInt(0), .arguments = arguments } } };
    const functions = try a.dupe(typed.Function, &.{
        .{
            .id = @fromBackingInt(0),
            .name = "pick",
            .declaration = span,
            .signature = .{ .parameter_count = count, .return_type = list, .return_origin = .{ .params = &.{ 0, 64, 129 } } },
            .scope = .{ .body = @fromBackingInt(0), .locals = locals[0..count] },
        },
        .{ .id = @fromBackingInt(1), .name = "caller", .declaration = span, .signature = .{ .parameter_count = count, .return_type = .unit }, .scope = .{ .body = @fromBackingInt(0), .locals = locals } },
    });
    const program: typed.Program = .{
        .nodes = nodes,
        .statements = &.{.{ .span = span, .terminates = false, .data = .{ .initialize = .{ .slot = @fromBackingInt(count), .value = @fromBackingInt(count) } } }},
        .functions = functions,
        .records = &.{.{ .id = @fromBackingInt(0), .name = "List", .declaration = span, .managed = true, .fields = &.{}, .shape = .{ .buffer = .i64 } }},
        .main = @fromBackingInt(1),
    };
    const roots = (try callRoots(a, program, @fromBackingInt(count))).?.roots.?;
    try std.testing.expectEqualSlices(u32, &.{ 0, 64, 129 }, roots);
    try markCallViews(a, program);
    try std.testing.expect(locals[count].ownership.view);
    // A nonlocal source cannot be omitted to make the other roots look valid.
    nodes[129].data = .{ .array = &.{} };
    try std.testing.expect((try callRoots(a, program, @fromBackingInt(count))).?.roots == null);
}

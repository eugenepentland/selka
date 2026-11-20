//! The `simd` module's lane operations on `Simd` values: `splat`, `load`, `store`, `select`, `sum`,
//! `min`, `max` and `fma`. The compiler checks each call against its operands and, for `splat` and
//! `load`, against the type its context expects, which gives the lane count. The module declares the
//! names for the public surface; the declarations are never called.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const numeric_surface = @import("numeric_surface.zig");
const collections = @import("collection_lower.zig");
const Error = diagnostic.Error;

/// The lane operations, by the name a call spells after `simd.`; `builtin_functions.zig` owns the list, since each is a
/// `builtin func` of the `simd` module.
const Operation = @import("builtin_functions.zig").LaneOperation;

/// The lane operation a call spells on the `simd` module, as `simd.max(...)` or with an owner. A local
/// named `simd` is not the module, and a call the module does not declare is no lane call.
fn laneOperation(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?Operation {
    _ = @sizeOf(Checker);
    const text = self.src.text(call.name);
    const name = if (call.owner) |owner| blk: {
        if (!std.mem.eql(u8, self.src.text(owner), "simd")) return null;
        break :blk text;
    } else blk: {
        if (!std.mem.startsWith(u8, text, "simd.")) return null;
        break :blk text["simd.".len..];
    };
    if (self.active.contains("simd")) return null;
    return std.meta.stringToEnum(Operation, name);
}

/// Whether a call spells one of the lane operations on the `simd` module.
pub fn isLaneCall(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
    return laneOperation(Checker, self, call) != null;
}

/// Whether an operand is a `simd.splat` call. A binary operator gives such an operand the lane type and count of
/// its other operand (SIMD-SPLAT-INFER-1), so the checker checks that operand first.
pub fn isSplatOperand(comptime Checker: type, self: *Checker, id: ast.NodeId) bool {
    const node = self.syntax.nodes.items[@backingInt(id)];
    if (node.data != .call) return false;
    return laneOperation(Checker, self, node.data.call) == .splat;
}

/// Check one lane call. Its arguments are already checked (the call pre-pass queues them).
pub fn check(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    const operation = laneOperation(Checker, self, call) orelse return self.sink.fail("E_SIMD_OPERATOR", node.span, "not a simd lane operation");
    return checkOperation(Checker, self, node, call, operation, out);
}

/// Check one lane call whose operation the caller resolved (W10): an import alias, a re-export, keyword arguments bound
/// to positions, or the `builtin func` declaration's own body. `call.arguments` are in parameter order.
pub fn checkOperation(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), operation: Operation, out: *typed.Node) Error!void {
    return switch (operation) {
        .splat => splat(Checker, self, node, call, out),
        .load => load(Checker, self, node, call, out),
        .store => store(Checker, self, node, call, out),
        .select => select(Checker, self, node, call, out),
        .sum, .min, .max => reduce(Checker, self, node, call, operation, out),
        .fma => fused(Checker, self, node, call, out),
        .sqrt => squareRoot(Checker, self, node, call, out),
    };
}

/// The checked argument at `position` of the call.
fn argument(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), position: usize) typed.NodeId {
    _ = @sizeOf(Checker);
    return self.resolved.at(@backingInt(call.arguments[position])).?;
}

/// The lane type and count a call's context expects: the `Simd` type of the expected annotation.
fn expectedLanes(comptime Checker: type, self: *Checker, node: ast.Node, name: []const u8) Error!typed.Array {
    _ = @sizeOf(Checker);
    const message = try std.fmt.allocPrint(self.allocator, "simd.{s} takes its lane count from the Simd type its context expects; annotate the binding or pass it to a Simd parameter", .{name});
    const expected = self.expected_types.get(node.span) orelse return self.sink.fail("E_SIMD_CONTEXT", node.span, message);
    return numeric_surface.vectorShape(expected, self.catalog.records) orelse self.sink.fail("E_SIMD_CONTEXT", node.span, "the expected type is not a Simd type");
}

/// The Simd type a context expects, as a type identity.
fn expectedType(comptime Checker: type, self: *Checker, node: ast.Node) typed.Type {
    _ = @sizeOf(Checker);
    return self.expected_types.get(node.span).?;
}

fn splat(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "simd.splat takes one lane value");
    const shape = try expectedLanes(Checker, self, node, "splat");
    const vector = expectedType(Checker, self, node);
    const value = try adoptLane(Checker, self, argument(Checker, self, call, 0), shape.element);
    try self.require(self.nodes.items[@backingInt(value)].ty, shape.element, node.span);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const lane = try b.local(shape.element);
    const values = try self.allocator.alloc(typed.NodeId, shape.length);
    for (values) |*item| item.* = try b.read(lane);
    out.* = try b.block(&.{try b.stmt(.{ .initialize = .{ .slot = lane, .value = value } })}, try b.node(vector, .{ .array = values }));
}

fn load(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    if (call.arguments.len != 2) return self.sink.fail("E_ARITY", node.span, "simd.load takes a list and an index");
    var slot = try listLocal(Checker, self, call, 0, node.span);
    const element = self.locals.items[@backingInt(slot)].ty;
    const shape = try expectedLanes(Checker, self, node, "load");
    const vector = expectedType(Checker, self, node);
    const element_type = listElement(self.catalog.records, element) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.load reads a list whose elements are the Simd lane type");
    try self.require(element_type, shape.element, node.span);
    const index = argument(Checker, self, call, 1);
    try self.require(self.nodes.items[@backingInt(index)].ty, .i64, node.span);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const first = try b.local(.i64);
    var setup: [2]typed.StatementId = undefined;
    var setup_len: usize = 0;
    const input = argument(Checker, self, call, 0);
    if (self.nodes.items[@backingInt(input)].own) {
        slot = try b.readOwner(element);
        setup[setup_len] = try b.stmt(.{ .initialize = .{ .slot = slot, .value = input } });
        setup_len += 1;
    }
    setup[setup_len] = try b.stmt(.{ .initialize = .{ .slot = first, .value = index } });
    setup_len += 1;
    const values = try self.allocator.alloc(typed.NodeId, shape.length);
    for (values, 0..) |*item, k| item.* = try b.operation(slot, .read, &.{try b.binary(.add, try b.read(first), try b.integer(@intCast(k)), .i64)});
    out.* = try b.block(setup[0..setup_len], try b.node(vector, .{ .array = values }));
}

fn store(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    if (call.arguments.len != 3) return self.sink.fail("E_ARITY", node.span, "simd.store takes a mut list, an index and a Simd value");
    if (self.syntax.nodes.items[@backingInt(call.arguments[0])].data != .mut_argument) return self.sink.failOwnership(.{ .code = "E_MUTATION_MARKER", .rule = .M3 }, node.span, "simd.store writes its list; pass it with `mut`");
    const slot = try listLocal(Checker, self, call, 0, node.span);
    const element = listElement(self.catalog.records, self.locals.items[@backingInt(slot)].ty) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.store writes a list whose elements are the Simd lane type");
    const value = argument(Checker, self, call, 2);
    const vector_type = self.nodes.items[@backingInt(value)].ty;
    const shape = numeric_surface.vectorShape(vector_type, self.catalog.records) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.store writes a Simd value");
    try self.require(shape.element, element, node.span);
    const index = argument(Checker, self, call, 1);
    try self.require(self.nodes.items[@backingInt(index)].ty, .i64, node.span);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const first = try b.local(.i64);
    const lanes = try b.local(vector_type);
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = first, .value = index } }));
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = lanes, .value = value } }));
    for (0..shape.length) |k| {
        const at = try b.binary(.add, try b.read(first), try b.integer(@intCast(k)), .i64);
        const lane = try b.node(element, .{ .index = .{ .base = try b.read(lanes), .index = try b.integer(@intCast(k)) } });
        try statements.append(self.allocator, try b.stmt(.{ .discard = try b.operation(slot, .write, &.{ at, lane }) }));
    }
    out.* = try b.block(statements.items, try b.node(.unit, .unit));
}

fn select(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    if (call.arguments.len != 3) return self.sink.fail("E_ARITY", node.span, "simd.select takes a mask and two Simd values");
    const mask = argument(Checker, self, call, 0);
    const a = argument(Checker, self, call, 1);
    const b = argument(Checker, self, call, 2);
    const mask_type = self.nodes.items[@backingInt(mask)].ty;
    const lanes = numeric_surface.vectorShape(self.nodes.items[@backingInt(a)].ty, self.catalog.records) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.select picks between Simd values");
    const mask_shape = numeric_surface.vectorShape(mask_type, self.catalog.records) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.select takes a Simd mask");
    if (mask_shape.element != .bool or mask_shape.length != lanes.length) return self.sink.fail("E_SIMD_ARGUMENT", node.span, "the mask has the lane count of the values");
    try self.require(self.nodes.items[@backingInt(b)].ty, self.nodes.items[@backingInt(a)].ty, node.span);
    out.* = .{ .span = node.span, .ty = self.nodes.items[@backingInt(a)].ty, .data = .{ .vector_select = .{ .mask = mask, .a = a, .b = b, .op_span = node.span } } };
}

/// `simd.sum`, `simd.min` and `simd.max`: a fold over the lanes in order, the same comparison the scalar
/// `min` and `max` make (`min` keeps the earlier lane unless a later one is smaller, `max` likewise).
fn reduce(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), operation: Operation, out: *typed.Node) Error!void {
    if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "simd.sum, simd.min and simd.max take one Simd value");
    const value = argument(Checker, self, call, 0);
    const vector_type = self.nodes.items[@backingInt(value)].ty;
    const shape = numeric_surface.vectorShape(vector_type, self.catalog.records) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.sum, simd.min and simd.max take a Simd value");
    const element = shape.element;
    if (element == .bool) return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.sum, simd.min and simd.max fold float, f32 or integer lanes");
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const lanes = try b.local(vector_type);
    const acc = try b.local(element);
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = lanes, .value = value } }));
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = acc, .value = try b.node(element, .{ .index = .{ .base = try b.read(lanes), .index = try b.integer(0) } }) } }));
    for (1..shape.length) |k| {
        const lane = try b.node(element, .{ .index = .{ .base = try b.read(lanes), .index = try b.integer(@intCast(k)) } });
        switch (operation) {
            .sum => {
                const sum = try foldSum(Checker, self, acc, lane, element);
                try statements.append(self.allocator, try b.stmt(.{ .assign = .{ .slot = acc, .value = sum } }));
            },
            .min, .max => {
                const condition = try foldCondition(Checker, self, operation, acc, lane, element);
                try statements.append(self.allocator, try b.stmt(.{ .branch = .{
                    .condition = condition,
                    .then_body = try b.stmt(.{ .assign = .{ .slot = acc, .value = lane } }),
                    .else_body = null,
                } }));
            },
            else => unreachable,
        }
    }
    out.* = try b.block(statements.items, try b.read(acc));
}

/// The running sum of a fold: checked integer addition on integer lanes, the float sum otherwise.
fn foldSum(comptime Checker: type, self: *Checker, acc: typed.LocalId, lane: typed.NodeId, element: typed.Type) Error!typed.NodeId {
    const span = self.nodes.items[@backingInt(lane)].span;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    if (element.isInteger()) return b.binary(.add, try b.read(acc), lane, element);
    const numbers = numeric_surface.Builder{ .arena = self.allocator, .nodes = &self.nodes, .span = span, .float_type = element, .records = self.catalog.records };
    return numbers.append(try numbers.binary(.add, try b.read(acc), lane, self.sink));
}

/// The comparison a min or max fold makes: `max` takes a later lane when the accumulated one is smaller,
/// `min` when the later lane is smaller, so ties keep the earlier lane.
fn foldCondition(comptime Checker: type, self: *Checker, operation: Operation, acc: typed.LocalId, lane: typed.NodeId, element: typed.Type) Error!typed.NodeId {
    const span = self.nodes.items[@backingInt(lane)].span;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const earlier = try b.read(acc);
    const left = if (operation == .max) earlier else lane;
    const right = if (operation == .max) lane else earlier;
    if (element.isInteger()) return b.binary(.lt, left, right, .bool);
    const numbers = numeric_surface.Builder{ .arena = self.allocator, .nodes = &self.nodes, .span = span, .float_type = element, .records = self.catalog.records };
    return numbers.append(try numbers.binary(.lt, left, right, self.sink));
}

/// A splat's lane value, adopted to the lane type when it is a literal: an integer literal takes an integer
/// lane type (refused when it does not fit), and an unsuffixed float literal takes f32 lanes.
fn adoptLane(comptime Checker: type, self: *Checker, value: typed.NodeId, element: typed.Type) Error!typed.NodeId {
    const node = self.nodes.items[@backingInt(value)];
    if (node.data == .integer and element.isInteger() and node.ty != element) {
        if (node.data.integer < element.min() or node.data.integer > element.max()) return self.sink.fail("E_TYPE", node.span, "the literal does not fit the Simd lane type");
        self.nodes.items[@backingInt(value)].ty = element;
        return value;
    }
    if (node.data == .wrap and numeric_surface.isFloat(node.ty, self.catalog.records) and numeric_surface.isF32(element, self.catalog.records)) {
        const builder = numeric_surface.Builder{ .arena = self.allocator, .nodes = &self.nodes, .span = node.span, .float_type = element, .records = self.catalog.records };
        return builder.append(try builder.literal(self.src.text(node.span), self.sink));
    }
    return value;
}

fn fused(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    if (call.arguments.len != 3) return self.sink.fail("E_ARITY", node.span, "simd.fma takes three Simd values");
    const a = argument(Checker, self, call, 0);
    const vector_type = self.nodes.items[@backingInt(a)].ty;
    const lanes = numeric_surface.vectorShape(vector_type, self.catalog.records) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.fma takes Simd values");
    if (!numeric_surface.isBinaryFloat(lanes.element, self.catalog.records)) return self.sink.fail("E_SIMD_LANE", node.span, "simd.fma rounds float or f32 lanes once; integer lanes have no fused form");
    for (call.arguments[1..]) |item| try self.require(self.nodes.items[@backingInt(self.resolved.at(@backingInt(item)).?)].ty, vector_type, node.span);
    const b = argument(Checker, self, call, 1);
    const c = argument(Checker, self, call, 2);
    out.* = .{ .span = node.span, .ty = vector_type, .data = .{ .float_fma = .{ .a = a, .b = b, .c = c, .op_span = node.span } } };
}

/// `simd.sqrt`: the square root of each lane of a float or f32 `Simd` value, one vector `sqrt` (SIMD-SQRT-1).
fn squareRoot(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "simd.sqrt takes one Simd value");
    const value = argument(Checker, self, call, 0);
    const vector_type = self.nodes.items[@backingInt(value)].ty;
    const lanes = numeric_surface.vectorShape(vector_type, self.catalog.records) orelse return self.sink.fail("E_SIMD_ARGUMENT", node.span, "simd.sqrt takes a Simd value");
    if (!numeric_surface.isBinaryFloat(lanes.element, self.catalog.records)) return self.sink.fail("E_SIMD_LANE", node.span, "simd.sqrt takes float or f32 lanes");
    out.* = .{ .span = node.span, .ty = vector_type, .data = .{ .vector_sqrt = .{ .operand = value, .op_span = node.span } } };
}

/// The list local a call's first argument names, which an operation on the list must write or read.
fn listLocal(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), position: usize, span: source.Span) Error!typed.LocalId {
    _ = @sizeOf(Checker);
    const id = argument(Checker, self, call, position);
    const checked = self.nodes.items[@backingInt(id)];
    if (checked.data != .local) return self.sink.fail("E_SIMD_ARGUMENT", span, "simd.load and simd.store name a list variable");
    return checked.data.local;
}

/// The element type of a list, or null when the type is not a list.
fn listElement(records: []const typed.Record, ty: typed.Type) ?typed.Type {
    if (!ty.isAggregate()) return null;
    const record = records[ty.recordIndex()];
    if (record.collection.kind != .list) return null;
    return record.shape.buffer;
}

//! Provider lifetimes follow an enclosing owned record, with no field-sensitive loans.
const std = @import("std");
const typed = @import("mylang").typed;
const ir = @import("ir.zig");
const none = std.math.maxInt(usize);
pub const Error = error{UnsupportedInstruction};

/// Compiler-only borrowed marker; its physical type is part of the exact identity.
pub const prefix = "myl_core_provider_pin_";

/// Streams and Host are scalar tokens; other capabilities own native provider state.
pub fn leaf(ty: typed.Type) bool {
    return ty.capabilityIndex() != null and !ty.isStream() and ty != .host_cap;
}

const Edge = struct { parent: usize, next: usize };
const Graph = struct {
    allocator: std.mem.Allocator,
    heads: []usize,
    marked: []bool,
    edges: std.ArrayList(Edge) = .empty,

    fn add(self: *Graph, parent: usize, child: typed.Type) !void {
        if (leaf(child)) {
            self.marked[parent] = true;
        } else if (child.isAggregate()) {
            const index = child.recordIndex();
            try self.edges.append(self.allocator, .{ .parent = parent, .next = self.heads[index] });
            self.heads[index] = self.edges.items.len - 1;
        }
    }

    fn record(self: *Graph, parent: usize, value: typed.Record) !void {
        for (value.fields) |field| try self.add(parent, field.ty);
        if (value.shape.buffer) |element| try self.add(parent, element);
        if (value.collection.key) |key| try self.add(parent, key);
        if (value.shape.array) |array| try self.add(parent, array.element);
        if (value.shape.variants) |variants| for (variants.cases) |variant| {
            if (variant.payload) |payload| try self.add(parent, payload);
        };
        if (value.shape.domain) |wire| try self.add(parent, wire);
    }
};

/// Find provider-containing source types once, in O(types + storage edges).
/// Cycles cannot cache an incomplete false result: seeds propagate over reverse edges.
pub fn classify(a: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error![]bool {
    const marked = try a.alloc(bool, program.records.len);
    errdefer a.free(marked);
    @memset(marked, false);
    const heads = try a.alloc(usize, marked.len);
    defer a.free(heads);
    @memset(heads, none);
    var graph: Graph = .{ .allocator = a, .heads = heads, .marked = marked };
    defer graph.edges.deinit(a);
    for (program.records, 0..) |record, parent| try graph.record(parent, record);
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(a);
    for (marked, 0..) |present, index| if (present) try queue.append(a, index);
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        var edge = heads[queue.items[cursor]];
        while (edge != none) {
            const item = graph.edges.items[edge];
            if (!marked[item.parent]) {
                marked[item.parent] = true;
                try queue.append(a, item.parent);
            }
            edge = item.next;
        }
    }
    return marked;
}

/// Query the completed source-type facts without traversing another type graph.
pub fn contains(facts: []const bool, ty: typed.Type) bool {
    return leaf(ty) or (ty.isAggregate() and facts[ty.recordIndex()]);
}

/// Scoped field providers must be projections of a named local, not temporaries.
pub fn root(program: typed.Program, source: typed.NodeId) ?typed.LocalId {
    var cursor = source;
    while (true) switch (program.nodes[@backingInt(cursor)].data) {
        .local => |slot| return slot,
        .field => |field| cursor = field.base,
        else => return null,
    };
}

/// Admit provider ownership only through ordinary record fields in this closeout.
pub fn plainRecord(record: typed.Record) bool {
    if (record.managed or record.collection.box or record.isCollection()) return false;
    if (record.shape.array != null or record.shape.variants != null or record.shape.resource != null) return false;
    if (record.shape.domain != null or record.contract.callback != null) return false;
    for (record.fields) |field| if (field.boxed) return false;
    return true;
}

/// Parse only a canonical generated physical-type identity, never an open prefix.
pub fn markerType(symbol: []const u8) ?ir.Type {
    if (!std.mem.startsWith(u8, symbol, prefix)) return null;
    const number = symbol[prefix.len..];
    if (number.len == 0 or number[0] == '0') return null;
    for (number) |byte| if (byte < '0' or byte > '9') return null;
    const id = std.fmt.parseInt(u32, number, 10) catch return null;
    const ty: ir.Type = @fromBackingInt(id);
    return if (ty.isCompound()) ty else null;
}

/// Validate the complete borrowed compiler marker before omitting its machine code.
pub fn marker(module: *const ir.Module, function: *const ir.Function) error{UnsupportedInstruction}!bool {
    if (!std.mem.startsWith(u8, function.name, prefix)) return false;
    if (!module.zero_rc) return error.UnsupportedInstruction;
    const ty = markerType(function.name) orelse return error.UnsupportedInstruction;
    if (@backingInt(ty) - ir.Type.first_compound >= module.compounds.items.len) return error.UnsupportedInstruction;
    const signature = function.signature;
    if (module.kind(ty) != .record or signature.linkage != .runtime_c or signature.ret != .void) return error.UnsupportedInstruction;
    if (signature.params.len != 1 or signature.params[0] != ty) return error.UnsupportedInstruction;
    if (signature.owned != 0 or signature.consumes != 0 or signature.views != 0) return error.UnsupportedInstruction;
    if (function.blocks.items.len != 0 or function.insts.items.len != 0) return error.UnsupportedInstruction;
    return true;
}

fn operands(function: *const ir.Function, data: u64) Error![]const ir.Ref {
    const range = ir.ExtraSlice.unpack(data);
    if (range.start > function.extra.items.len or range.len > function.extra.items.len - range.start) return error.UnsupportedInstruction;
    return function.extra.items[range.start..][0..range.len];
}

/// Core observes this borrow until lexical cleanup; emitted code needs no operation.
pub fn call(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Error!bool {
    if (inst.op != .call) return false;
    if (inst.a == .none or inst.a.index() >= module.functions.items.len) return error.UnsupportedInstruction;
    const callee = &module.functions.items[inst.a.index()];
    if (!try marker(module, callee)) return false;
    if (inst.ty != .void) return error.UnsupportedInstruction;
    const args = try operands(function, inst.data);
    if (args.len != 1) return error.UnsupportedInstruction;
    const argument = try @import("borrow_selection.zig").resolve(function, args[0]);
    if (function.inst(argument).ty != callee.signature.params[0]) return error.UnsupportedInstruction;
    return true;
}

/// Cheap discovery; the shared wrapper validates callee indices before this query.
pub fn hasMarker(module: *const ir.Module, function: *const ir.Function) bool {
    for (function.insts.items) |inst| {
        if (inst.op != .call or inst.a == .none or inst.a.index() >= module.functions.items.len) continue;
        if (std.mem.startsWith(u8, module.functions.items[inst.a.index()].name, prefix)) return true;
    }
    return false;
}

/// Check exact call tables before the shared CFG/type/dominance verifier runs.
pub fn validate(module: *const ir.Module, function: *const ir.Function) Error!void {
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        if (ref == .none or ref.index() >= function.insts.items.len) return error.UnsupportedInstruction;
    };
    for (function.insts.items) |inst| {
        if (!module.valid(inst.ty)) return error.UnsupportedInstruction;
        if (inst.op.hasExtra()) _ = try operands(function, inst.data);
        const values = function.valueOperands(inst);
        for (0..values.len()) |index| _ = try @import("borrow_selection.zig").resolve(function, values.get(index));
        _ = try call(module, function, inst);
    }
}

/// Pin the current SSA owner without copying, retaining or inspecting its children.
pub fn keepalive(comptime Context: type, builder: Context, value: ir.Ref, span: u32) error{ OutOfMemory, Unsupported }!void {
    const ty = builder.typeOfRef(value);
    const symbol = if (ty == .capability) "myl_core_provider_keepalive" else try std.fmt.allocPrint(builder.allocator(), "{s}{d}", .{ prefix, @backingInt(ty) });
    _ = try builder.effectCall(symbol, &.{ty}, .void, &.{value}, span);
}

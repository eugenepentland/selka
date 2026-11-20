//! Verify actual borrowed result storage against the declaration's projected owners.
const std = @import("std");
const ir = @import("ir.zig");
const selections = @import("borrow_selection.zig");

const Node = struct { value: ir.Ref, path: []const ir.BorrowProjection };
const Edge = struct { block: usize, position: usize, previous: ?*const Edge };

/// Every reachable returned borrowed leaf must originate in a declared argument
/// or in the exact final owner returned alongside it. Empty wrapper alternatives
/// and static storage need no owner. No body-derived contract is inferred.
pub fn valid(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function, returned: ir.Ref) std.mem.Allocator.Error!bool {
    if (function.signature.borrow.sources.len == 0) return false;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var walker: Walker = .{ .allocator = scratch.allocator(), .module = module, .function = function, .returned = returned };
    const accepted = try walker.check(returned, function.signature.borrow.path, null);
    return accepted and walker.anchors != 0;
}

const Walker = struct {
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    function: *const ir.Function,
    returned: ir.Ref,
    active: std.ArrayList(Node) = .empty,
    anchors: usize = 0,

    fn check(self: *Walker, value: ir.Ref, path: []const ir.BorrowProjection, edges: ?*const Edge) std.mem.Allocator.Error!bool {
        const node = (try self.normalize(.{ .value = value, .path = path }, edges)) orelse return false;
        if (node.value == .none or try self.allowed(node, edges)) {
            self.anchors += 1;
            return true;
        }
        for (self.active.items) |active| if (sameNode(active, node)) return true;
        try self.active.append(self.allocator, node);
        defer self.active.items.len -= 1;
        const inst = self.function.inst(node.value);
        if (inst.op == .phi) {
            const block = self.blockOf(node.value) orelse return false;
            for (self.function.operands(inst.data), 0..) |operand, position| {
                const edge: Edge = .{ .block = block, .position = position, .previous = edges };
                if (!try self.check(operand, node.path, &edge)) return false;
            }
            return true;
        }
        if (inst.op == .call) return self.call(node, inst, edges);
        // A borrowed record (1A) is made of lent fields: every managed field must come from a declared owner.
        if (inst.op == .record_make and node.path.len == 0 and self.module.isBorrowed(inst.ty)) {
            for (self.function.operands(inst.data)) |field| {
                if (!self.module.managed(self.function.inst(self.function.resolve(field)).ty)) continue;
                if (!try self.check(field, &.{}, edges)) return false;
            }
            return true;
        }
        // A field or payload projected from a collection element remains a
        // subobject of the collection owner. The selected path does not change
        // which declared root keeps that storage alive.
        if (node.path.len != 0) return switch (inst.op) {
            .list_get, .list_get_field, .dict_entry_key, .dict_entry_value, .array_get, .box_get, .box_take => self.check(inst.a, &.{}, edges),
            else => false,
        };
        return switch (inst.op) {
            .str_const, .undef, .text_sentinel => blk: {
                self.anchors += 1;
                break :blk true;
            },
            .borrow,
            .str_view_of,
            .str_slice_view,
            .str_slice_bytes_view,
            .list_view_of,
            .list_slice_view,
            .list_get,
            .list_get_field,
            .dict_entry_key,
            .dict_entry_value,
            .array_get,
            .box_get,
            .box_take,
            => self.check(inst.a, &.{}, edges),
            .text_frame => self.check(inst.b, &.{}, edges),
            // A lent option of a borrowed record (`Some(owner.a)`, RB1): its payload must come from a declared owner.
            .union_make => if (inst.a == .none or !self.module.managed(self.function.inst(self.function.resolve(inst.a)).ty)) blk: {
                self.anchors += 1;
                break :blk true;
            } else self.check(inst.a, &.{}, edges),
            else => false,
        };
    }

    fn call(self: *Walker, node: Node, inst: ir.Inst, edges: ?*const Edge) std.mem.Allocator.Error!bool {
        if (inst.a == .none or inst.a.index() >= self.module.functions.items.len) return false;
        if (node.path.len == 0) if (selections.call(self.module, self.function, inst) catch return false) |selection| {
            const dictionary = try self.check(selection.dictionary, &.{}, edges);
            if (!dictionary) return false;
            return self.check(selection.fallback, &.{}, edges);
        };
        // The callee's contract lends the part of its result at `contract.path` from its sources, so every part inside that
        // part (a field of a lent record, the payload of a lent option) is the sources' storage too: `pick(xs).name`, where
        // `pick` lends from `xs`, is `xs`'s (FX16). A part outside it (a sibling field of a partly lent record) is not.
        const contract = self.module.functions.items[inst.a.index()].signature.borrow;
        if (contract.sources.len == 0 or !insidePath(node.path, contract.path)) return false;
        const arguments = self.function.operands(inst.data);
        for (contract.sources) |source| switch (source) {
            .argument => |position| {
                if (position >= arguments.len) return false;
                if (!try self.check(arguments[position], &.{}, edges)) return false;
            },
            .result => |owner| if (!try self.check(node.value, owner, edges)) return false,
        };
        return true;
    }

    fn allowed(self: *Walker, node: Node, edges: ?*const Edge) std.mem.Allocator.Error!bool {
        const inst = self.function.inst(node.value);
        for (self.function.signature.borrow.sources) |source| switch (source) {
            .argument => |position| if (inst.op == .param and inst.data == position) return true,
            .result => |path| {
                const owner = (try self.normalize(.{ .value = self.returned, .path = path }, edges)) orelse return false;
                if (owner.value == node.value and owner.path.len <= node.path.len and ir.samePath(owner.path, node.path[0..owner.path.len])) return true;
                if (try self.partOfOwner(owner, node, edges)) return true;
            },
        };
        return false;
    }

    /// Whether `node` is a part of the final owner `owner` that an update of the owner's other fields left in place: a
    /// `mut` parameter that writes `self.index` and returns `self.entries[i]` returns a borrow of the entries the updated
    /// record still holds, which normalizes to the parameter's own field (F-RA-115). Each tail of the node's path is
    /// appended to the owner's and normalized; the part is the owner's when one names the node.
    fn partOfOwner(self: *Walker, owner: Node, node: Node, edges: ?*const Edge) std.mem.Allocator.Error!bool {
        var tail: usize = 1;
        while (tail <= node.path.len) : (tail += 1) {
            const steps = node.path[node.path.len - tail ..];
            const path = try self.allocator.alloc(ir.BorrowProjection, owner.path.len + steps.len);
            @memcpy(path[0..owner.path.len], owner.path);
            @memcpy(path[owner.path.len..], steps);
            const part = (try self.normalize(.{ .value = owner.value, .path = path }, edges)) orelse continue;
            if (sameNode(part, node)) return true;
        }
        return false;
    }

    fn normalize(self: *Walker, start: Node, edges: ?*const Edge) std.mem.Allocator.Error!?Node {
        var node = start;
        var remaining = self.function.insts.items.len + 1;
        // The phis this normalization resolved through an edge. An edge names the predecessor of one entry of its block, and
        // a walk that has gone back around a loop (`hub = inst.ref_des` after a `continue`: two phis that feed each other)
        // reaches that block again at an earlier entry the edge does not describe. A phi met twice is left unresolved, and
        // `check` walks every one of its operands.
        var resolved: std.ArrayList(ir.Ref) = .empty;
        while (remaining != 0) : (remaining -= 1) {
            node.value = selections.resolve(self.function, node.value) catch return null;
            if (node.value == .none) return null;
            const inst = self.function.inst(node.value);
            switch (inst.op) {
                .borrow => node.value = inst.a,
                .record_get, .union_payload, .union_take => {
                    const step: ir.BorrowProjection = if (inst.op == .record_get) .{ .field = @intCast(inst.data) } else .{ .payload = @intCast(inst.data) };
                    const path = try self.allocator.alloc(ir.BorrowProjection, node.path.len + 1);
                    path[0] = step;
                    @memcpy(path[1..], node.path);
                    node = .{ .value = inst.a, .path = path };
                },
                .record_make => {
                    if (node.path.len == 0) return node;
                    if (node.path[0] != .field) return null;
                    const fields = self.function.operands(inst.data);
                    const index = node.path[0].field;
                    if (index >= fields.len) return null;
                    node = .{ .value = fields[index], .path = node.path[1..] };
                },
                .record_set => {
                    if (node.path.len == 0) return node;
                    if (node.path[0] != .field) return null;
                    node = if (node.path[0].field == inst.data) .{ .value = inst.b, .path = node.path[1..] } else .{ .value = inst.a, .path = node.path };
                },
                .union_make => {
                    if (node.path.len == 0) return node;
                    if (node.path[0] != .payload) return null;
                    if (node.path[0].payload != inst.data) return .{ .value = .none, .path = &.{} };
                    node = .{ .value = inst.a, .path = node.path[1..] };
                },
                .phi => {
                    const block = self.blockOf(node.value) orelse return null;
                    const position = edgePosition(edges, block) orelse return node;
                    if (std.mem.indexOfScalar(ir.Ref, resolved.items, node.value) != null) return node;
                    try resolved.append(self.allocator, node.value);
                    const incoming = self.function.operands(inst.data);
                    if (position >= incoming.len) return null;
                    if (incoming[position] == node.value) return node;
                    node.value = incoming[position];
                },
                else => return node,
            }
        }
        return null;
    }

    fn blockOf(self: *const Walker, value: ir.Ref) ?usize {
        for (self.function.blocks.items, 0..) |block, index| if (std.mem.indexOfScalar(ir.Ref, block.insts.items, value) != null) return index;
        return null;
    }
};

fn edgePosition(edges: ?*const Edge, block: usize) ?usize {
    var edge = edges;
    while (edge) |at| : (edge = at.previous) if (at.block == block) return at.position;
    return null;
}

/// Whether `path` names `lent` or a part inside it: `lent` is a prefix of `path`.
fn insidePath(path: []const ir.BorrowProjection, lent: []const ir.BorrowProjection) bool {
    return path.len >= lent.len and ir.samePath(path[0..lent.len], lent);
}

fn sameNode(a: Node, b: Node) bool {
    return a.value == b.value and ir.samePath(a.path, b.path);
}

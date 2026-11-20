//! The `ownership-certificate-v2` form and text of a program's final Core IR
//! (docs/design/ownership-certificates.md §4.1).
//!
//! The exporter serializes three things and nothing else: the final instructions, the operation table
//! (`ownership_ops.zig`) and the states the ownership pass kept (`ownership_certificate.zig`). It decides
//! no ownership itself. `build` turns one function into the in-memory form the validator checks
//! (`ownership_function.zig`); `write` prints a form as text, the same bytes every run: values are numbered by
//! their instruction index, blocks by their index, and every list is in operand or block order.
const std = @import("std");
const ir = @import("ir.zig");
const ops = @import("ownership_ops.zig");
const certificate = @import("ownership_certificate.zig");
const form = @import("ownership_function.zig");
const flags = @import("flags.zig");
const elements = @import("elements.zig");
const transfers = @import("transfers.zig");
const State = certificate.State;

/// The first line of every certificate file.
pub const magic = "ownership-certificate-v2";

/// A function the exporter could not describe, and why. Nothing of it is written.
pub const Problem = struct {
    function: []const u8,
    reason: []const u8,
};

/// What `render` counted, for the corpus report.
pub const Counts = struct {
    functions: u32 = 0,
    /// Functions described with an `unchecked` reason: none since C6 (design §10), kept for the corpus report.
    unchecked_task_group: u32 = 0,
    problems: u32 = 0,
};

/// The inputs the exporter needs: the final module, the tables the ownership pass kept and where to put
/// the functions it could not describe.
pub const Request = struct {
    module: *const ir.Module,
    sink: *const certificate.Sink,
    problems: *std.ArrayList(Problem),
};

/// The text of one certificate file holding the functions `indices` of `request.module`, in that order.
pub fn render(a: std.mem.Allocator, request: Request, indices: []const u32, counts: *Counts) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try writeHeader(a, &out);
    for (indices) |index| {
        const function = &request.module.functions.items[index];
        if (function.signature.linkage != .internal) continue;
        switch (try build(a, request.module, request.sink, index)) {
            .described => |described| {
                counts.functions += 1;
                if (described.unchecked != null) counts.unchecked_task_group += 1;
                try write(a, &out, described);
            },
            .refused => |reason| {
                counts.problems += 1;
                try request.problems.append(a, .{ .function = function.name, .reason = reason });
            },
        }
    }
    return out.toOwnedSlice(a);
}

/// The first lines of a certificate file: the version line and the operation-class table, one line per `ir.Op`.
pub fn writeHeader(a: std.mem.Allocator, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    try out.print(a, "{s}\n", .{magic});
    for (std.enums.values(ir.Op)) |op| try out.print(a, "class {s} {s}\n", .{ @tagName(op), ops.classOf(op).token() });
}

/// A function name as one token of a certificate file: a byte at or below `0x20`, `0x7f` or `\` is written `\xHH`.
pub fn escapedName(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text) |byte| {
        if (byte <= 0x20 or byte == 0x7f or byte == '\\') {
            try out.print(a, "\\x{x:0>2}", .{byte});
        } else try out.append(a, byte);
    }
    return out.toOwnedSlice(a);
}

/// What `build` answers: the function's form, or why the exporter cannot describe it.
pub const Built = union(enum) { described: form.Function, refused: []const u8 };

/// The form of function `index` of `module`, from the table the ownership pass kept in `sink`.
pub fn build(a: std.mem.Allocator, module: *const ir.Module, sink: *const certificate.Sink, index: u32) std.mem.Allocator.Error!Built {
    const f = &module.functions.items[index];
    const capture = sink.get(index) orelse return .{ .refused = "the ownership pass did not run on it" };
    var builder: Builder = .{ .a = a, .module = module, .f = f, .capture = capture };
    return builder.run();
}

/// Builds the form of one function. `settle` first fixes the state and parents of every value; the instruction
/// builders then read them.
const Builder = struct {
    a: std.mem.Allocator,
    module: *const ir.Module,
    f: *const ir.Function,
    capture: certificate.Capture,
    states: []State = &.{},
    /// Per instruction: some other instruction, phi or terminator names it as an operand.
    used: []bool = &.{},
    /// Per instruction: some lend lends to it (a group). Built when a function abandons owners.
    groups: []bool = &.{},
    parents: []const []const form.Parent = &.{},
    /// The callees of the calls built so far, in the order the calls first use them.
    callees: std.ArrayList(form.Callee) = .empty,
    reason: []const u8 = "",
    /// Per instruction: the store is paired with a transferred read of its slot (`transfers.slots`, the
    /// same answer the emitter acts on), so it releases nothing.
    transferred: []const bool = &.{},
    /// The instructions of the block being built and the position of the one being built.
    block: []const ir.Ref = &.{},
    position: usize = 0,

    fn run(self: *Builder) std.mem.Allocator.Error!Built {
        if (!try self.settle()) return .{ .refused = self.reason };
        const f = self.f;
        const placed = try self.a.alloc(bool, f.insts.items.len);
        @memset(placed, false);
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            for (block.insts.items) |ref| placed[ref.index()] = true;
        }
        var pre: std.ArrayList(form.Inst) = .empty;
        for (f.insts.items, 0..) |inst, i| {
            if (placed[i] or !inst.op.isConstant()) continue;
            try pre.append(self.a, try self.instruction(@fromBackingInt(@as(u32, @intCast(i)))));
        }
        var blocks: std.ArrayList(form.Block) = .empty;
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            try blocks.append(self.a, try self.buildBlock(@intCast(b), block));
        }
        if (self.reason.len != 0) return .{ .refused = self.reason };
        var params: std.ArrayList(form.Param) = .empty;
        const header = try headerOf(self.a, self.module, f.signature);
        for (header.modes, 0..) |mode, i| {
            try params.append(self.a, .{ .value = @intCast(self.paramValue(i).?), .state = paramState(mode) });
        }
        return .{ .described = .{
            .name = f.name,
            .returns = header.returns,
            .unchecked = null,
            .params = params.items,
            .callees = self.callees.items,
            .pre = pre.items,
            .blocks = blocks.items,
        } };
    }

    /// Fix the state and parents of every instruction; false (with `reason`) when one cannot be described.
    fn settle(self: *Builder) std.mem.Allocator.Error!bool {
        const f = self.f;
        const n = f.insts.items.len;
        self.transferred = try transfers.slots(self.a, f);
        const states = try self.a.alloc(State, n);
        const parents = try self.a.alloc([]const form.Parent, n);
        for (0..n) |i| {
            const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(i)));
            const inst = f.inst(ref);
            var list: std.ArrayList(form.Parent) = .empty;
            const state = self.stateOf(i, inst) orelse {
                self.reason = try std.fmt.allocPrint(self.a, "instruction %{d} ({s}) is beyond the ownership table and has no derived state", .{ i, @tagName(inst.op) });
                return false;
            };
            states[i] = state;
            if (self.inconsistent(inst, state)) |why| {
                self.reason = try std.fmt.allocPrint(self.a, "instruction %{d} ({s}): {s}", .{ i, @tagName(inst.op), why });
                return false;
            }
            if (state == .owned or state == .borrowed) {
                if (inst.op == .param) {
                    if (state == .borrowed) try list.append(self.a, .{ .caller = @intCast(inst.data) });
                } else if (inst.op == .text_frame) {
                    // The cache owner is the parameter's own block or a header in this frame; it frames the span `b`
                    // and lives as long as it does, so a borrow of the frame is a borrow of that span's owner.
                    states[i] = .borrowed;
                    try list.append(self.a, .{ .value = @intCast(f.resolve(inst.b).index()) });
                } else for (self.capture.parents(i)) |parent| try list.append(self.a, .{ .value = @intCast(f.resolve(parent).index()) });
            }
            parents[i] = list.items;
        }
        self.states = states;
        self.parents = parents;
        try self.dropConsumedHolders(parents);
        try self.reparentForwardViews(parents);
        self.used = try self.operandSet();
        // A value of the unit type that something names as an operand (a unit stored in a `dict[K, Unit]`) gets a name and
        // the state `none`: it owns nothing, and consuming it changes nothing.
        for (states, 0..) |*state, i| {
            if (f.insts.items[i].ty == .void and f.insts.items[i].op != .copy and self.used[i]) state.* = .none;
        }
        for (0..f.signature.params.len) |position| {
            if (self.paramValue(position) == null) {
                self.reason = try std.fmt.allocPrint(self.a, "parameter {d} has no value in the body", .{position});
                return false;
            }
        }
        return true;
    }

    /// An owned aggregate takes over the loans of the owners it consumes, so its result lists as parents only the views it
    /// reads (design §3, Construct; the checker admits the parents of an owned value among its read operands, J1). The pass
    /// also names a consumed operand that holds a loan (a record that wraps a union holding a view, as a call with a `mut`
    /// argument returns it); that operand is inherited, not a view the aggregate reads, so it is left out here.
    fn dropConsumedHolders(self: *Builder, parents: [][]const form.Parent) std.mem.Allocator.Error!void {
        const f = self.f;
        for (f.insts.items, 0..) |inst, i| {
            // An owned phi consumes its operands and so holds what they held (a collection of borrows across a loop, RB2): it
            // reads nothing to lend.
            if (inst.op == .phi and self.states[i] == .owned) {
                parents[i] = &.{};
                continue;
            }
            if (inst.op != .record_make and inst.op != .union_make and !self.module.lentStore(inst)) continue;
            if (self.states[i] != .owned or parents[i].len == 0) continue;
            var reads: std.ArrayList(u32) = .empty;
            var consumes: std.ArrayList(u32) = .empty;
            try self.operandRoles(inst, &reads, &consumes);
            var kept: std.ArrayList(form.Parent) = .empty;
            for (parents[i]) |parent| switch (parent) {
                .value => |value| if (std.mem.indexOfScalar(u32, consumes.items, value) == null or std.mem.indexOfScalar(u32, reads.items, value) != null)
                    try kept.append(self.a, parent),
                .caller => try kept.append(self.a, parent),
            };
            parents[i] = kept.items;
        }
    }

    /// A borrowed view of a slot that an owned read of the same slot takes later in the same block, and that nothing reads
    /// before the take, is a view of the value the take defines: they are the same allocation, and the view lives as long as
    /// the take does (a forward take, design §3). The table lists the container as its parent.
    fn reparentForwardViews(self: *Builder, parents: [][]const form.Parent) std.mem.Allocator.Error!void {
        const f = self.f;
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            const refs = block.insts.items;
            for (refs, 0..) |ref, i| {
                const inst = f.inst(ref);
                if (self.states[ref.index()] != .borrowed or ops.classOf(inst.op) != .project or parents[ref.index()].len != 1) continue;
                const head: u32 = @intCast(f.resolve(inst.a).index());
                switch (parents[ref.index()][0]) {
                    .value => |parent| if (parent != head) continue,
                    .caller => continue,
                }
                const key = (try self.extras(ref, inst, .borrowed)).slot orelse continue;
                const take = (try self.laterTake(refs, i, key)) orelse continue;
                const list = try self.a.alloc(form.Parent, 1);
                list[0] = .{ .value = take };
                parents[ref.index()] = list;
            }
        }
    }

    /// The owned read of slot `key` of the container that the view at position `at` of `refs` reads, defined later in the
    /// block, provided no instruction between them reads the view; null otherwise.
    fn laterTake(self: *Builder, refs: []const ir.Ref, at: usize, key: []const u8) std.mem.Allocator.Error!?u32 {
        const f = self.f;
        const view = refs[at];
        const container = f.resolve(f.inst(view).a);
        for (refs[at + 1 ..]) |ref| {
            const inst = f.inst(ref);
            if (self.readsValue(inst, view)) return null;
            if (ops.classOf(inst.op) != .project or self.states[ref.index()] != .owned or f.resolve(inst.a) != container) continue;
            const slot = (try self.extras(ref, inst, .owned)).slot orelse continue;
            if (std.mem.eql(u8, slot, key)) return @intCast(ref.index());
        }
        return null;
    }

    /// Whether `inst` names `value` among its operands.
    fn readsValue(self: *Builder, inst: ir.Inst, value: ir.Ref) bool {
        const f = self.f;
        if (inst.op == .copy) return false;
        if (inst.op == .phi) {
            for (f.operands(inst.data)) |operand| if (f.resolve(operand) == value) return true;
            return false;
        }
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |k| if (f.resolve(operands.get(k)) == value) return true;
        return false;
    }

    /// The instructions some instruction, phi or terminator of a listed block names as an operand.
    fn operandSet(self: *Builder) std.mem.Allocator.Error![]bool {
        const f = self.f;
        const used = try self.a.alloc(bool, f.insts.items.len);
        @memset(used, false);
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op == .copy) continue;
                if (inst.op == .phi) {
                    for (f.operands(inst.data)) |operand| used[f.resolve(operand).index()] = true;
                    continue;
                }
                const operands = f.valueOperands(inst);
                for (0..operands.len()) |k| {
                    const at = f.resolve(operands.get(k));
                    if (at != .none) used[at.index()] = true;
                }
            }
        }
        return used;
    }

    /// The state of instruction `index`: the pass's table when it covers it, else the state the
    /// instructions added after the analysis always have.
    fn stateOf(self: *Builder, index: usize, inst: ir.Inst) ?State {
        if (self.capture.state(index)) |state| return if (inst.op == .text_frame) .borrowed else state;
        if (inst.op == .copy or inst.ty == .void) return .none;
        if (!self.module.managed(inst.ty) and !self.module.containsBorrow(inst.ty)) return .scalar;
        return switch (inst.op) {
            // A cleanup phi carries an owner on the paths that built it and the null owner on the rest.
            .phi => .owned,
            .undef => .immortal,
            else => null,
        };
    }

    /// A state that contradicts a marker the instruction itself carries in the final IR: the table cannot
    /// describe the function until the pass and the marker agree.
    fn inconsistent(self: *Builder, inst: ir.Inst, state: State) ?[]const u8 {
        // A transferred read owns the element it takes; when owned reads take every managed part of that element, the
        // pass leaves the element itself `emptied` (`takeFields`), which the certificate states and J8 checks.
        if (flags.transferredRead(inst) and self.module.managed(inst.ty) and state != .owned and state != .emptied) return "a transferred read whose result is not owned";
        if (state == .stack and inst.op == .list_new and (inst.data == 0 or flags.isFillCapacity(inst.data))) return "a stack list that promotion did not mark";
        if (state == .stack and inst.op == .list_new and self.module.managed(self.module.compound(inst.ty).list)) return "a stack list of managed elements";
        if (inst.op == .box_make and inst.data & flags.lent_box != 0 and self.f.resolve(inst.b) == .none) return "a lent box that names no group";
        return null;
    }

    /// The value naming parameter `position`: the `param` instruction that reads it. Every parameter has one.
    fn paramValue(self: *Builder, position: usize) ?usize {
        for (self.f.insts.items, 0..) |inst, i| if (inst.op == .param and inst.data == position) return i;
        return null;
    }

    /// The entry block, or a block with predecessors: the emitter skips the rest.
    fn present(self: *Builder, b: usize) bool {
        return b == 0 or self.f.blocks.items[b].preds.items.len != 0;
    }

    fn buildBlock(self: *Builder, id: u32, block: ir.Block) std.mem.Allocator.Error!form.Block {
        const f = self.f;
        var preds: std.ArrayList(u32) = .empty;
        for (block.preds.items) |pred| try preds.append(self.a, @backingInt(pred));
        var phis: std.ArrayList(form.Phi) = .empty;
        var insts: std.ArrayList(form.Inst) = .empty;
        var term: form.Term = .unreachable_path;
        self.block = block.insts.items;
        for (block.insts.items, 0..) |ref, position| {
            const inst = f.inst(ref);
            if (inst.op == .copy) continue;
            self.position = position;
            if (inst.op.terminates()) {
                term = self.terminator(inst);
            } else if (inst.op == .phi) {
                try phis.append(self.a, try self.phi(ref, inst, block.preds.items));
            } else try insts.append(self.a, try self.instruction(ref));
        }
        return .{ .id = id, .preds = preds.items, .abandons = try self.abandonsInto(id), .phis = phis.items, .insts = insts.items, .term = term };
    }

    /// The `abandon` lines of block `id`: for each predecessor, the owners the pass left undestroyed on the edge because a trap
    /// follows (`certificate.Abandon`), in ascending order. A lent-to group is never abandoned: its tasks read the lent cells until
    /// the process ends, so it stays live (design §9, entry 55).
    fn abandonsInto(self: *Builder, id: u32) std.mem.Allocator.Error![]const form.Abandon {
        var lists: std.ArrayList(form.Abandon) = .empty;
        for (self.capture.abandons) |gone| {
            if (gone.to != id or !self.present(gone.from)) continue;
            const value: u32 = @intCast(self.f.resolve(gone.value).index());
            if (self.states[value] != .owned or try self.lentTo(value)) continue;
            var at: ?usize = null;
            for (lists.items, 0..) |list, i| if (list.from == gone.from) {
                at = i;
            };
            if (at == null) {
                try lists.append(self.a, .{ .from = gone.from, .values = &.{} });
                at = lists.items.len - 1;
            }
            const list = &lists.items[at.?];
            if (std.mem.indexOfScalar(u32, list.values, value) != null) continue;
            const grown = try self.a.alloc(u32, list.values.len + 1);
            @memcpy(grown[0..list.values.len], list.values);
            grown[list.values.len] = value;
            list.values = grown;
        }
        std.mem.sort(form.Abandon, lists.items, {}, abandonBefore);
        for (lists.items) |*list| {
            const sorted = try self.a.dupe(u32, list.values);
            std.mem.sort(u32, sorted, {}, std.sort.asc(u32));
            list.values = sorted;
        }
        return lists.items;
    }

    fn abandonBefore(_: void, x: form.Abandon, y: form.Abandon) bool {
        return x.from < y.from;
    }

    /// Whether some lend of the function lends to `value`.
    fn lentTo(self: *Builder, value: u32) std.mem.Allocator.Error!bool {
        if (self.groups.len == 0) {
            self.groups = try self.a.alloc(bool, self.f.insts.items.len);
            @memset(self.groups, false);
            for (self.f.insts.items) |inst| {
                if (inst.op == .box_make and inst.data & flags.lent_box != 0 and inst.b != .none) self.groups[self.f.resolve(inst.b).index()] = true;
            }
        }
        return self.groups[value];
    }

    fn phi(self: *Builder, ref: ir.Ref, inst: ir.Inst, preds: []const ir.BlockId) std.mem.Allocator.Error!form.Phi {
        var edges: std.ArrayList(form.Edge) = .empty;
        for (self.f.operands(inst.data), preds) |operand, pred| {
            try edges.append(self.a, .{ .block = @backingInt(pred), .value = @intCast(self.f.resolve(operand).index()) });
        }
        return .{ .value = @intCast(ref.index()), .result = .{ .state = self.states[ref.index()], .parents = self.parents[ref.index()] }, .edges = edges.items };
    }

    fn terminator(self: *Builder, inst: ir.Inst) form.Term {
        return switch (inst.op) {
            .jump => .{ .jump = @intCast(inst.data) },
            .branch => blk: {
                const targets = ir.unpackTargets(inst.data);
                break :blk .{ .branch = .{ .condition = @intCast(self.f.resolve(inst.a).index()), .then = @backingInt(targets.then), .otherwise = @backingInt(targets.otherwise) } };
            },
            .ret => .{ .ret = if (inst.a == .none) null else @as(u32, @intCast(self.f.resolve(inst.a).index())) },
            else => .unreachable_path,
        };
    }

    fn instruction(self: *Builder, ref: ir.Ref) std.mem.Allocator.Error!form.Inst {
        const inst = self.f.inst(ref);
        const i = ref.index();
        var reads: std.ArrayList(u32) = .empty;
        var consumes: std.ArrayList(u32) = .empty;
        try self.operandRoles(inst, &reads, &consumes);
        return .{
            .value = if (inst.ty != .void or self.used[i]) @intCast(i) else null,
            .op = inst.op,
            .class = ops.classOf(inst.op),
            .reads = reads.items,
            .consumes = consumes.items,
            .result = .{ .state = self.states[i], .parents = self.parents[i] },
            .extras = try self.extras(ref, inst, self.states[i]),
        };
    }

    /// The slot a container instruction reads, takes or stores, what a store destroys, the fields of an emptied
    /// record and the values a call result may borrow from (design §3, the slot protocol).
    fn extras(self: *Builder, ref: ir.Ref, inst: ir.Inst, state: State) std.mem.Allocator.Error!form.Extras {
        const m = self.module;
        const f = self.f;
        var out: form.Extras = .{};
        switch (inst.op) {
            .record_get => if (m.managed(inst.ty)) {
                out.slot = try std.fmt.allocPrint(self.a, "f{d}", .{inst.data});
            },
            .record_set => if (m.managed(m.compound(m.storageType(inst.ty)).record[@intCast(inst.data)])) {
                out.slot = try std.fmt.allocPrint(self.a, "f{d}", .{inst.data});
            },
            .array_get => if (m.managed(inst.ty)) {
                out.slot = try self.indexSlot('e', inst.b, null);
            },
            .array_set => if (m.managed(m.compound(m.storageType(inst.ty)).array.elem)) {
                out.slot = try self.indexSlot('e', inst.b, null);
            },
            .list_get => if (m.managed(inst.ty)) {
                out.slot = try self.indexSlot('e', inst.b, null);
            },
            .list_set => if (m.managed(m.compound(m.storageType(inst.ty)).list)) {
                out.slot = try self.indexSlot('e', inst.b, null);
                out.released = .{ .old = !self.transferred[ref.index()] };
            },
            .list_get_field => if (m.managed(inst.ty)) {
                out.slot = try self.indexSlot('e', inst.b, ir.FieldPath.unpack(inst.data & ~flags.place_read));
            },
            .list_set_field => {
                const element = m.compound(m.storageType(inst.ty)).list;
                if (elements.setPath(f, inst)) |path| if (m.pathTarget(element, path)) |target| if (m.managed(target.ty)) {
                    out.slot = try self.indexSlot('e', inst.b, path);
                    out.released = .{ .old = !self.transferred[ref.index()] };
                };
            },
            .dict_entry_key => if (m.managed(inst.ty)) {
                out.slot = try self.indexSlot('k', inst.b, null);
            },
            .dict_entry_value => if (m.managed(inst.ty)) {
                out.slot = try self.indexSlot('v', inst.b, null);
            },
            .dict_set_value => if (m.managed(m.compound(m.storageType(inst.ty)).dict.value)) {
                out.slot = try self.indexSlot('v', inst.b, null);
                out.released = .{ .old = !self.transferred[ref.index()] };
            },
            .dict_remove => {
                const shape = m.compound(m.storageType(inst.ty)).dict;
                const taken = (inst.data & flags.dict_take_mask) >> 56;
                if (m.managed(shape.key) or m.managed(shape.value)) {
                    out.slot = try self.indexSlot('v', inst.b, null);
                    out.released = .{ .key = m.managed(shape.key) and taken & 1 == 0, .value = m.managed(shape.value) and taken & 2 == 0 };
                    out.taken = .{ .key = m.managed(shape.key) and taken & 1 != 0, .value = m.managed(shape.value) and taken & 2 != 0 };
                }
            },
            .list_pop => if (m.managed(m.compound(m.storageType(inst.ty)).list)) {
                out.slot = try self.poppedSlot(inst);
            },
            .call, .call_indirect => out.call = .{ .from = try self.callFrom(inst, ref.index()), .callee = try self.calleeFor(inst) },
            .box_make => if (inst.data & flags.lent_box != 0) {
                out.loans.lent = @intCast(f.resolve(inst.b).index());
            },
            .iconst, .cmp, .fcmp => out.imm = inst.data,
            else => {},
        }
        if (state == .emptied) out.slots = try self.emptiedSlots(inst);
        // A take whose result type cannot hold a view hands no loans on: whatever the aggregate it leaves lends is not in it.
        if (ops.classOf(inst.op) == .take and state == .owned and !m.containsBorrow(inst.ty)) out.loans.noloans = true;
        if (ops.classOf(inst.op) == .construct and out.loans.lent == null and (state == .owned or state == .emptied))
            out.loans.views = try self.viewsOf(inst);
        return out;
    }

    /// The borrowed operands constructor `inst` reads into a slot whose type its destruction does not destroy: the views it
    /// may hold as loans (format v2, `views`). A borrowed `str`, list, dictionary or managed record is not one: the
    /// aggregate's destruction would destroy it (J6 `construct-read`, condition 2).
    fn viewsOf(self: *Builder, inst: ir.Inst) std.mem.Allocator.Error![]const u32 {
        const operands = self.f.valueOperands(inst);
        var views: std.ArrayList(u32) = .empty;
        for (0..operands.len()) |k| {
            const ref = self.f.resolve(operands.get(k));
            if (ref == .none or self.states[ref.index()] != .borrowed or self.consumed(inst, k, .borrowed)) continue;
            if (self.module.managed(self.slotType(inst, k, ref))) continue;
            try self.addUnique(&views, @intCast(ref.index()));
        }
        return views.items;
    }

    /// The type of the slot constructor `inst` stores operand `position` (`ref`) in: a record's field, a union case's
    /// payload, a box's content; the operand's own type when the aggregate's type says nothing more.
    fn slotType(self: *Builder, inst: ir.Inst, position: usize, ref: ir.Ref) ir.Type {
        const m = self.module;
        const ty = m.storageType(inst.ty);
        if (ty.isCompound() and m.valid(ty)) switch (m.compound(ty)) {
            .record => |fields| if (inst.op == .record_make and position < fields.len) return fields[position],
            .@"union" => |cases| if (inst.op == .union_make and inst.data < cases.len) return cases[@intCast(inst.data)],
            .box => |inner| if (inst.op == .box_make) return inner,
            else => {},
        };
        return self.f.insts.items[ref.index()].ty;
    }

    /// `KIND%N`, `KIND#C` or, with a field path, `KIND%NpA.B`: the element an index names.
    fn indexSlot(self: *Builder, kind: u8, index: ir.Ref, path: ?ir.FieldPath) std.mem.Allocator.Error![]const u8 {
        const at = self.f.resolve(index);
        const constant = self.f.inst(at);
        var out: std.ArrayList(u8) = .empty;
        if (constant.op == .iconst) {
            try out.print(self.a, "{c}#{d}", .{ kind, @as(i64, @bitCast(constant.data)) });
        } else try out.print(self.a, "{c}%{d}", .{ kind, at.index() });
        if (path) |steps| {
            try out.append(self.a, 'p');
            for (steps.slice(), 0..) |step, i| try out.print(self.a, "{s}{d}", .{ if (i == 0) "" else ".", step });
        }
        return out.items;
    }

    /// A pop removes the last element without releasing it: an owned read of that element came first
    /// (`own.markPops` finds the last `list_get` of the list in the block), or the pass added one after.
    fn poppedSlot(self: *Builder, inst: ir.Inst) std.mem.Allocator.Error![]const u8 {
        const list = self.f.resolve(inst.a);
        var back = self.position;
        while (back > 0) {
            back -= 1;
            const earlier = self.f.inst(self.block[back]);
            if (earlier.op == .list_get and self.f.resolve(earlier.a) == list) return self.indexSlot('e', earlier.b, null);
        }
        return "tail";
    }

    /// The managed fields of an emptied record: each is taken by exactly one owned read of the record.
    fn emptiedSlots(self: *Builder, inst: ir.Inst) std.mem.Allocator.Error![]const []const u8 {
        const m = self.module;
        const fields = m.compound(m.storageType(inst.ty)).record;
        var keys: std.ArrayList([]const u8) = .empty;
        for (fields, 0..) |field, k| {
            if (m.managed(field)) try keys.append(self.a, try std.fmt.allocPrint(self.a, "f{d}", .{k}));
        }
        return keys.items;
    }

    /// The entry of the callee table for the call `inst`: the callee's `function` line as its own certificate states it (name, the
    /// state of each parameter and how it is passed, the kind of result, the `from` positions), added when the call is the first
    /// to use it. An indirect call names the function type's signature, once per distinct signature.
    fn calleeFor(self: *Builder, inst: ir.Inst) std.mem.Allocator.Error!u32 {
        const f = self.f;
        const direct = inst.op == .call;
        const target = if (direct) self.module.functions.items[inst.a.index()] else null;
        const signature = if (target) |function| function.signature else self.module.compound(f.inst(f.resolve(inst.a)).ty).@"fn";
        const header = try headerOf(self.a, self.module, signature);
        const kind: form.CalleeKind = if (!direct) .indirect else calleeKind(target.?);
        const name: []const u8 = if (target) |function| function.name else "";
        for (self.callees.items) |known| {
            if (known.kind != kind or !std.mem.eql(u8, known.name, name) or known.result != header.returns.kind) continue;
            if (std.mem.eql(form.ParamMode, known.params, header.modes) and std.mem.eql(u32, known.from, header.returns.from)) return known.id;
        }
        const id: u32 = @intCast(self.callees.items.len);
        try self.callees.append(self.a, .{ .id = id, .name = name, .kind = kind, .params = header.modes, .result = header.returns.kind, .from = header.returns.from });
        return id;
    }

    /// The values the callee's `from` contract says the result borrows from (design §3, Call), plus any other
    /// parent the pass recorded for the call (a reserved marker call names its own).
    fn callFrom(self: *Builder, inst: ir.Inst, index: usize) std.mem.Allocator.Error![]const u32 {
        const f = self.f;
        const signature = if (inst.op == .call) self.module.functions.items[inst.a.index()].signature else self.module.compound(f.inst(f.resolve(inst.a)).ty).@"fn";
        const arguments = f.operands(inst.data);
        var values: std.ArrayList(u32) = .empty;
        for (signature.borrow.sources) |source| switch (source) {
            .argument => |position| if (position < arguments.len) try self.addUnique(&values, @intCast(f.resolve(arguments[position]).index())),
            .result => {},
        };
        for (self.parents[index]) |parent| switch (parent) {
            .value => |value| try self.addUnique(&values, value),
            .caller => {},
        };
        return values.items;
    }

    fn addUnique(self: *Builder, values: *std.ArrayList(u32), value: u32) std.mem.Allocator.Error!void {
        if (std.mem.indexOfScalar(u32, values.items, value) == null) try values.append(self.a, value);
    }

    /// Split the value operands of `inst` into the ones it reads and the ones it consumes (design §3). A scalar
    /// or immortal operand is listed like any other: consuming one is a no-op for the checker.
    fn operandRoles(self: *Builder, inst: ir.Inst, reads: *std.ArrayList(u32), consumes: *std.ArrayList(u32)) std.mem.Allocator.Error!void {
        const f = self.f;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |k| {
            const ref = f.resolve(operands.get(k));
            if (ref == .none) continue;
            const state = self.states[ref.index()];
            if (self.consumed(inst, k, state)) {
                try consumes.append(self.a, @intCast(ref.index()));
            } else try reads.append(self.a, @intCast(ref.index()));
        }
    }

    fn consumed(self: *Builder, inst: ir.Inst, position: usize, operand: State) bool {
        switch (inst.op) {
            .call => return self.module.functions.items[inst.a.index()].signature.passing.takes(position),
            .call_indirect => {
                if (position == 0) return false;
                const callee = self.f.inst(self.f.resolve(inst.a));
                return self.module.compound(callee.ty).@"fn".passing.takes(position - 1);
            },
            // A borrowed operand of a return or an aggregate is lent on, not given away (R4).
            .ret, .union_make, .record_make => if (operand == .borrowed) return false,
            // An element stored into a collection of borrows (RB2) is lent to it.
            .list_push, .list_set, .dict_set_value, .dict_insert => if (operand == .borrowed and position != 0 and self.module.lentStore(inst)) return false,
            else => {},
        }
        return ops.consumesAt(inst, position);
    }
};

/// What a function with `signature` returns: a borrow of its arguments, an owner, or a scalar.
fn resultKindOf(module: *const ir.Module, signature: ir.Signature) form.ResultKind {
    const managed = module.managed(signature.ret);
    if (signature.borrow.sources.len != 0 and (signature.borrow.path.len == 0 or !managed)) return .borrowed;
    return if (managed) .owned else .scalar;
}

/// What a function's `function` and `param` lines say of its signature, and so what a callee table entry says of a callee: how
/// each parameter is passed together with the state the callee's own `param` line gives it, the kind of result and the `from`
/// positions of its borrow contract. One derivation serves both, so an entry cannot differ from the callee's own certificate.
const Header = struct { modes: []const form.ParamMode, returns: form.Returns };

fn headerOf(a: std.mem.Allocator, module: *const ir.Module, signature: ir.Signature) std.mem.Allocator.Error!Header {
    const modes = try a.alloc(form.ParamMode, signature.params.len);
    for (signature.params, modes, 0..) |param, *mode, i| {
        const holds = module.managed(param) or module.containsBorrow(param);
        const takes = signature.passing.takes(i);
        mode.* = if (takes) (if (holds) .take else .take_scalar) else (if (holds) .read else .read_scalar);
    }
    var from: std.ArrayList(u32) = .empty;
    for (signature.borrow.sources) |source| switch (source) {
        .argument => |position| try from.append(a, position),
        .result => {},
    };
    return .{ .modes = modes, .returns = .{ .kind = resultKindOf(module, signature), .from = from.items } };
}

/// The state a `param` line gives a parameter passed in `mode`: an unmanaged parameter is scalar whether or not it is taken.
fn paramState(mode: form.ParamMode) State {
    return switch (mode) {
        .take => .owned,
        .read => .borrowed,
        .take_scalar, .read_scalar => .scalar,
    };
}

/// Which kind of callee `function` is: a function of the program, a reserved marker call, a `myl_core_*` runtime function or
/// an `extern func`.
fn calleeKind(function: ir.Function) form.CalleeKind {
    if (function.signature.linkage == .internal) return .program;
    const markers = [_][]const u8{ "myl_core_borrow_select_v1_", "myl_core_borrow_choice_v1_", "myl_core_borrowed_provider_v1_", "myl_core_borrowed_optional_provider_v1_" };
    for (markers) |prefix| if (std.mem.startsWith(u8, function.name, prefix)) return .marker;
    return if (std.mem.startsWith(u8, function.name, "myl_core_")) .runtime else .@"extern";
}

/// Print `function` as the lines of a certificate file (design §4.1), after the class table.
pub fn write(a: std.mem.Allocator, out: *std.ArrayList(u8), function: form.Function) std.mem.Allocator.Error!void {
    var printer: Printer = .{ .a = a, .out = out };
    try printer.function(function);
}

const Printer = struct {
    a: std.mem.Allocator,
    out: *std.ArrayList(u8),

    fn function(self: *Printer, f: form.Function) std.mem.Allocator.Error!void {
        try self.out.appendSlice(self.a, "function ");
        try self.name(f.name);
        try self.out.print(self.a, " result {s} from ", .{@tagName(f.returns.kind)});
        try self.numbers(f.returns.from, "");
        try self.out.print(self.a, " unchecked {s}\n", .{if (f.unchecked) |reason| reason.token() else "-"});
        for (f.params, 0..) |param, i| try self.out.print(self.a, "param {d} %{d} {s}\n", .{ i, param.value, param.state.token() });
        for (f.callees) |callee| try self.calleeLine(callee);
        try self.out.appendSlice(self.a, "block b- preds -\n");
        for (f.pre) |inst| try self.line(inst);
        for (f.blocks) |block| {
            try self.out.print(self.a, "block b{d} preds ", .{block.id});
            if (block.preds.len == 0) try self.out.appendSlice(self.a, "-");
            for (block.preds, 0..) |pred, i| try self.out.print(self.a, "{s}b{d}", .{ if (i == 0) "" else ",", pred });
            try self.out.appendSlice(self.a, "\n");
            for (block.abandons) |gone| {
                try self.out.print(self.a, "abandon b{d} ", .{gone.from});
                try self.numbers(gone.values, "%");
                try self.out.appendSlice(self.a, "\n");
            }
            for (block.phis) |join| try self.phi(join);
            for (block.insts) |inst| try self.line(inst);
            try self.term(block.term);
        }
        try self.out.appendSlice(self.a, "end\n");
    }

    /// `callee N NAME KIND PARAMS RESULT FROM` (design §9, entry 57).
    fn calleeLine(self: *Printer, callee: form.Callee) std.mem.Allocator.Error!void {
        try self.out.print(self.a, "callee {d} ", .{callee.id});
        if (callee.name.len == 0) try self.out.appendSlice(self.a, "-") else try self.name(callee.name);
        try self.out.print(self.a, " {s} ", .{callee.kind.token()});
        if (callee.params.len == 0) try self.out.appendSlice(self.a, "-");
        for (callee.params, 0..) |mode, i| try self.out.print(self.a, "{s}{s}", .{ if (i == 0) "" else ",", mode.token() });
        try self.out.print(self.a, " {s} ", .{@tagName(callee.result)});
        try self.numbers(callee.from, "");
        try self.out.appendSlice(self.a, "\n");
    }

    /// A function name as one token: bytes that would split a line are written as `\xHH`.
    fn name(self: *Printer, text: []const u8) std.mem.Allocator.Error!void {
        try self.out.appendSlice(self.a, try escapedName(self.a, text));
    }

    /// A comma list of numbers, each after `prefix`; `-` when empty.
    fn numbers(self: *Printer, values: []const u32, prefix: []const u8) std.mem.Allocator.Error!void {
        if (values.len == 0) return self.out.appendSlice(self.a, "-");
        for (values, 0..) |value, i| try self.out.print(self.a, "{s}{s}{d}", .{ if (i == 0) "" else ",", prefix, value });
    }

    fn parents(self: *Printer, list: []const form.Parent) std.mem.Allocator.Error!void {
        if (list.len == 0) return self.out.appendSlice(self.a, "-");
        for (list, 0..) |parent, i| {
            try self.out.appendSlice(self.a, if (i == 0) "" else ",");
            switch (parent) {
                .value => |value| try self.out.print(self.a, "%{d}", .{value}),
                .caller => |position| try self.out.print(self.a, "^{d}", .{position}),
            }
        }
    }

    fn phi(self: *Printer, p: form.Phi) std.mem.Allocator.Error!void {
        try self.out.print(self.a, "phi %{d} {s} parents ", .{ p.value, p.result.state.token() });
        try self.parents(p.result.parents);
        try self.out.appendSlice(self.a, " edges ");
        for (p.edges, 0..) |edge, i| try self.out.print(self.a, "{s}b{d}:%{d}", .{ if (i == 0) "" else ",", edge.block, edge.value });
        try self.out.appendSlice(self.a, "\n");
    }

    fn term(self: *Printer, t: form.Term) std.mem.Allocator.Error!void {
        switch (t) {
            .jump => |target| try self.out.print(self.a, "term jump b{d}\n", .{target}),
            .branch => |branch| try self.out.print(self.a, "term branch %{d} b{d} b{d}\n", .{ branch.condition, branch.then, branch.otherwise }),
            .ret => |value| if (value) |v| try self.out.print(self.a, "term ret %{d}\n", .{v}) else try self.out.appendSlice(self.a, "term ret -\n"),
            .unreachable_path => try self.out.appendSlice(self.a, "term unreachable\n"),
        }
    }

    fn line(self: *Printer, i: form.Inst) std.mem.Allocator.Error!void {
        if (i.value) |value| try self.out.print(self.a, "inst %{d} ", .{value}) else try self.out.appendSlice(self.a, "inst - ");
        try self.out.print(self.a, "{s} {s} reads ", .{ @tagName(i.op), i.class.token() });
        try self.numbers(i.reads, "%");
        try self.out.appendSlice(self.a, " consumes ");
        try self.numbers(i.consumes, "%");
        try self.out.print(self.a, " state {s} parents ", .{i.result.state.token()});
        try self.parents(i.result.parents);
        const extras = i.extras;
        if (extras.slot) |key| try self.out.print(self.a, " slot {s}", .{key});
        if (extras.released) |set| try self.partsOf(" released ", set);
        if (extras.taken) |set| try self.partsOf(" taken ", set);
        if (extras.slots) |keys| {
            try self.out.appendSlice(self.a, " slots ");
            if (keys.len == 0) try self.out.appendSlice(self.a, "-");
            for (keys, 0..) |key, k| try self.out.print(self.a, "{s}{s}", .{ if (k == 0) "" else ",", key });
        }
        if (extras.call.from) |values| {
            try self.out.appendSlice(self.a, " from ");
            try self.numbers(values, "%");
        }
        if (extras.call.callee) |id| try self.out.print(self.a, " callee {d}", .{id});
        if (extras.loans.lent) |group| try self.out.print(self.a, " lent %{d}", .{group});
        if (extras.loans.noloans) try self.out.appendSlice(self.a, " noloans");
        if (extras.loans.views.len != 0) {
            try self.out.appendSlice(self.a, " views ");
            try self.numbers(extras.loans.views, "%");
        }
        if (extras.imm) |value| try self.out.print(self.a, " imm {d}", .{value});
        try self.out.appendSlice(self.a, "\n");
    }

    /// ` released old`, ` released key,value` and so on; `-` when the set is empty.
    fn partsOf(self: *Printer, label: []const u8, set: form.Parts) std.mem.Allocator.Error!void {
        try self.out.appendSlice(self.a, label);
        var wrote = false;
        inline for (.{ "old", "key", "value" }) |part| {
            if (@field(set, part)) {
                try self.out.print(self.a, "{s}{s}", .{ if (wrote) "," else "", part });
                wrote = true;
            }
        }
        if (!wrote) try self.out.appendSlice(self.a, "-");
    }
};

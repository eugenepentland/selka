//! Re-anchor nested field borrows in the newest owner that preserves their path.
//! Record reads cannot trap. Reading an unchanged path from a consuming update's
//! result preserves the snapshot while letting ownership end the old owner's life.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const effects = @import("effects.zig");
const origins = @import("inline_origins.zig");

const ReadKey = struct { call: ir.Ref, field: u32 };
const Change = struct { result: ir.Ref, writes: effects.Paths };
const Source = struct { root: ir.Ref, reads: [ir.FieldPath.max_steps]ir.Ref = undefined, len: usize = 0 };

/// Forward a borrow only across updates that leave its complete field path intact.
/// Phi operands remain on their original edges; all other replacements dominate use.
pub fn run(a: std.mem.Allocator, m: *const ir.Module, f: *ir.Function, summaries: *const effects.Summaries, origin: ?origins.Context) std.mem.Allocator.Error!void {
    const shape = try facts.shape(a, f);
    var reads: std.AutoHashMapUnmanaged(ReadKey, ir.Ref) = .empty;
    for (f.insts.items, 0..) |inst, i| {
        if (inst.op != .record_get) continue;
        const key: ReadKey = .{ .call = f.resolve(inst.a), .field = @intCast(inst.data) };
        const entry = try reads.getOrPut(a, key);
        if (!entry.found_existing) entry.value_ptr.* = @fromBackingInt(@intCast(i));
    }
    const positions = try a.alloc(usize, f.insts.items.len);
    for (f.blocks.items) |block| for (block.insts.items, 0..) |ref, at| {
        positions[ref.index()] = at;
    };
    const changes = try a.alloc(std.ArrayList(Change), f.insts.items.len);
    @memset(changes, .empty);
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .record_set) {
            var writes: effects.Paths = .{};
            _ = try writes.add(a, effects.child(.{}, @intCast(inst.data)));
            try changes[f.resolve(inst.a).index()].append(a, .{ .result = ref, .writes = writes });
        } else if (inst.op == .call) {
            const signature = m.functions.items[inst.a.index()].signature;
            for (f.operands(inst.data), 0..) |arg, k| {
                const final = effects.finalOf(m, signature, k) orelse continue;
                const result = switch (final) {
                    .whole => ref,
                    .field => |field| reads.get(.{ .call = ref, .field = field }) orelse continue,
                };
                try changes[f.resolve(arg).index()].append(a, .{ .result = result, .writes = summaries.of(inst.a.index(), k).writes });
            }
        }
    };
    const context: Context = .{ .a = a, .f = f, .shape = &shape, .changes = changes, .origin = origin, .positions = positions };
    for (f.blocks.items) |*block| {
        const original = try a.dupe(ir.Ref, block.insts.items);
        block.insts.clearRetainingCapacity();
        for (original) |ref| {
            var inst = f.inst(ref);
            if (inst.op != .copy and inst.op != .phi) {
                const operands = f.valueOperands(inst);
                // An extra slice is copied before appends can relocate its backing array.
                const extra = try a.dupe(ir.Ref, operands.extra);
                for (0..operands.direct_len) |k| {
                    const next = try context.forward(operands.direct[k], ref, &block.insts);
                    if (k == 0) inst.a = next else inst.b = next;
                }
                if (extra.len != 0) {
                    for (extra) |*arg| arg.* = try context.forward(arg.*, ref, &block.insts);
                    try replaceExtra(a, f, &inst, extra);
                }
                f.insts.items[ref.index()] = inst;
            }
            try block.insts.append(a, ref);
        }
    }
}

fn replaceExtra(a: std.mem.Allocator, f: *ir.Function, inst: *ir.Inst, extra: []const ir.Ref) !void {
    if (std.mem.eql(ir.Ref, extra, f.operands(inst.data))) return;
    const start: u32 = @intCast(f.extra.items.len);
    try f.extra.appendSlice(a, extra);
    inst.data = (ir.ExtraSlice{ .start = start, .len = @intCast(extra.len) }).pack();
}

const Context = struct {
    a: std.mem.Allocator,
    f: *ir.Function,
    shape: *const facts.Shape,
    changes: []const std.ArrayList(Change),
    origin: ?origins.Context,
    positions: []const usize,

    fn forward(self: Context, raw: ir.Ref, user: ir.Ref, out: *std.ArrayList(ir.Ref)) !ir.Ref {
        const f = self.f;
        const value = f.resolve(raw);
        const source = sourceOf(f, value) orelse return raw;
        var path: effects.Path = .{};
        var n = source.len;
        while (n > 0) {
            n -= 1;
            path = effects.child(path, @intCast(f.inst(source.reads[n]).data));
        }
        var root = source.root;
        var remaining = self.changes.len;
        while (root.index() < self.changes.len and remaining > 0) : (remaining -= 1) {
            const next = for (self.changes[root.index()].items) |change| {
                if (!change.writes.overlaps(path) and self.before(change.result, user)) break change.result;
            } else break;
            root = next;
        }
        if (root == source.root) return raw;
        n = source.len;
        while (n > 0) {
            n -= 1;
            const old = source.reads[n];
            var inst = f.inst(old);
            inst.a = root;
            root = @fromBackingInt(@intCast(f.insts.items.len));
            try f.insts.append(self.a, inst);
            if (self.origin) |origin| {
                const anchor = if (old.index() < self.shape.block_of.len) old else user;
                if (self.shape.block_of[anchor.index()]) |block| try origin.setInstruction(self.a, root, origin.at(@backingInt(block), anchor));
            }
            try out.append(self.a, root);
        }
        return root;
    }

    fn before(self: Context, definition: ir.Ref, user: ir.Ref) bool {
        const from = self.shape.block_of[definition.index()] orelse return false;
        const to = self.shape.block_of[user.index()] orelse return false;
        if (from == to) {
            // Block instruction lists are rebuilt, so compare original instruction
            // positions retained by the shape rather than the changing output list.
            return self.positions[definition.index()] < self.positions[user.index()];
        }
        var current: ?ir.BlockId = to;
        var left = self.f.blocks.items.len;
        while (current) |block| {
            if (block == from) return true;
            if (left == 0 or block.index() == 0) return false;
            left -= 1;
            current = self.shape.idom[block.index()];
        }
        return false;
    }
};

fn sourceOf(f: *const ir.Function, ref: ir.Ref) ?Source {
    var source: Source = .{ .root = ref };
    while (source.root != .none and f.inst(source.root).op == .record_get) {
        if (source.len == source.reads.len) return null;
        source.reads[source.len] = source.root;
        source.len += 1;
        source.root = f.resolve(f.inst(source.root).a);
    }
    return if (source.len == 0) null else source;
}

//! The fact-certificate exporter (docs/design/fact-certificates.md §10): the final IR and the fact tables the passes kept,
//! described in the form of `fact_function.zig`.
//!
//! It is a direct serialization of what `emit_llvm` will read, so it is trusted along with the passes (design §8, A5); the
//! validator never looks at `facts.zig`. A function that has no tables is described without any claim.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const form = @import("fact_function.zig");

const Allocator = std.mem.Allocator;

/// What the passes kept for a module: each function's final facts and the whole-program field intervals they were computed under.
pub const Tables = struct {
    /// Function `i`'s final facts, or null.
    known: []const ?facts.Facts,
    /// Empty when the facts were computed without field intervals (only the module's own types are consulted then).
    fields: facts.FieldIntervals = .{},
};

/// Describe every function of `module`, in module order (a function without a body has a header and nothing else, so that
/// a call's `#N` is the position in the file).
pub fn describe(a: Allocator, scratch: Allocator, module: *const ir.Module, tables: Tables) Allocator.Error!form.Module {
    const known = tables.known;
    const taken = try addressTaken(a, module);
    const returns = try returnIntervals(a, scratch, module, known);
    var found: std.ArrayList(form.Function) = .empty;
    for (module.functions.items, 0..) |*function, index| {
        var stated: ?facts.Facts = if (index < known.len) usable(known[index], function) else null;
        if (stated) |table| stated = try completed(a, scratch, .{ .module = module, .fields = tables.fields }, @constCast(function), table, returns);
        try found.append(a, try describeFunction(a, scratch, module, @constCast(function), stated, taken[index]));
    }
    return .{ .functions = found.items };
}

/// The interval each module function returns, from its final facts (null where it states none).
fn returnIntervals(a: Allocator, scratch: Allocator, module: *const ir.Module, known: []const ?facts.Facts) Allocator.Error![]?facts.Interval {
    const out = try a.alloc(?facts.Interval, module.functions.items.len);
    @memset(out, null);
    for (module.functions.items, out, 0..) |*function, *slot, index| {
        const tables = if (index < known.len) usable(known[index], function) else null;
        if (tables) |table| {
            var work = std.heap.ArenaAllocator.init(scratch);
            defer work.deinit();
            slot.* = try facts.returnRange(work.allocator(), &table, function, .none);
        }
    }
    return out;
}

/// The tables the exporter states for `f`: the passes' own, with the slots they left empty filled from a fresh analysis of the
/// final function. A pass that runs after the facts (ownership, forwarding, versioning) can add an instruction, which the
/// tables cover with no interval (`passes.extend`); the instructions that read it still carry the interval they had, and
/// the certificate can only show that interval follows from the new instruction's. Nothing the passes stated is replaced, so
/// the emitter reads what it always read.
fn completed(a: Allocator, scratch: Allocator, world: World, f: *ir.Function, table: facts.Facts, returns: []const ?facts.Interval) Allocator.Error!facts.Facts {
    const module = world.module;
    const field_table: facts.FieldIntervals = if (world.fields.module != null) world.fields else .{ .module = module };
    var params: std.ArrayList(?facts.Interval) = .empty;
    try params.resize(a, f.signature.params.len);
    @memset(params.items, null);
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .param and inst.data < params.items.len) params.items[@intCast(inst.data)] = table.ranges[index];
    }
    var work = std.heap.ArenaAllocator.init(scratch);
    defer work.deinit();
    const fresh = try facts.analyzeWithScratch(work.allocator(), work.allocator(), f, .{ .fold = false, .mark = false, .params = params.items, .returns = returns, .fields = field_table });
    const merged = try table.clone(a);
    for (merged.ranges, 0..) |*slot, index| {
        if (slot.* == null and index < fresh.ranges.len) slot.* = fresh.ranges[index];
    }
    try tighten(work.allocator(), f, merged, field_table);
    for (merged.aggregates.lists, 0..) |*slot, index| {
        if (!emptyList(slot.*) or index >= fresh.aggregates.lists.len) continue;
        const found = fresh.aggregates.lists[index];
        if (!emptyList(found)) slot.* = found;
    }
    return merged;
}

/// Close the tables under each instruction's transfer rule: an interval becomes the meet of the one stated and what the rule gives
/// from the intervals stated for the operands (at most three sweeps). Everything stated is already true of the final function, so
/// the meet is too. The passes state the instructions they add late and in other terms (a field's interval, a loop trip count that
/// the fresh analysis does not find), so an `add` can be stated wider than the phi that reads it, which the validator, deriving each
/// interval from its operands, would refuse. The emitter reads the passes' tables, not these: it reads no more than they say.
fn tighten(scratch: Allocator, f: *ir.Function, merged: facts.Facts, fields: facts.FieldIntervals) Allocator.Error!void {
    var viewer = try facts.Viewer.over(scratch, f, merged);
    viewer.useFields(fields);
    for (0..3) |_| {
        var changed = false;
        for (f.blocks.items, 0..) |block, position| {
            for (block.insts.items) |ref| {
                const index = ref.index();
                if (index >= merged.ranges.len) continue;
                const derived = viewer.derive(ref, @fromBackingInt(@intCast(position))) orelse continue;
                const old = merged.ranges[index];
                const next = if (old) |existing| existing.meet(derived) else derived;
                if (next.lo > next.hi or std.meta.eql(old, @as(?facts.Interval, next))) continue;
                merged.ranges[index] = next;
                changed = true;
            }
        }
        if (!changed) break;
    }
}

fn emptyList(fact: facts.ListFact) bool {
    return fact.len == null and fact.elements == null and fact.length == .none and !fact.pattern;
}

/// The module and its field intervals, for the analyses that complete a function's tables.
const World = struct { module: *const ir.Module, fields: facts.FieldIntervals };

/// Facts whose tables cover every instruction and block of `f`; anything else claims nothing.
fn usable(known: ?facts.Facts, f: *const ir.Function) ?facts.Facts {
    const table = known orelse return null;
    if (table.ranges.len != f.insts.items.len or table.reachable.len != f.blocks.items.len) return null;
    if (table.aggregates.lists.len != f.insts.items.len) return null;
    return table;
}

/// For each function, whether a `func_ref` takes its address (design §2.3): its parameters then have the type range.
fn addressTaken(a: Allocator, module: *const ir.Module) Allocator.Error![]bool {
    const out = try a.alloc(bool, module.functions.items.len);
    @memset(out, false);
    for (module.functions.items) |function| for (function.insts.items) |inst| {
        if (inst.op == .func_ref and inst.data < out.len) out[@intCast(inst.data)] = true;
    };
    return out;
}

/// The certificate's classification of an IR type.
pub fn typeOf(module: *const ir.Module, ty: ir.Type) form.Type {
    return switch (ty) {
        .void => .void,
        .bool => .bool,
        .i8 => .i8,
        .i16 => .i16,
        .i32 => .i32,
        .i64 => .i64,
        .u8 => .u8,
        .u16 => .u16,
        .u32 => .u32,
        .u64 => .u64,
        .f64 => .f64,
        else => if (ty.isCompound() and module.valid(ty) and isListLike(module, ty)) .list else .other,
    };
}

/// Lists, list views and fixed arrays carry the list facts (`len`, `elems`).
fn isListLike(module: *const ir.Module, ty: ir.Type) bool {
    const stored = module.storageType(ty);
    if (module.listElement(stored) != null) return true;
    return stored.isCompound() and module.kind(stored) == .array;
}

fn interval(range: ?facts.Interval) ?form.Interval {
    const known = range orelse return null;
    return .{ .lo = known.lo, .hi = known.hi };
}

/// Everything one function's description reads.
const Source = struct {
    module: *const ir.Module,
    f: *ir.Function,
    known: ?facts.Facts,
    viewer: *?facts.Viewer,
};

fn describeFunction(a: Allocator, scratch: Allocator, module: *const ir.Module, f: *ir.Function, known: ?facts.Facts, taken: bool) Allocator.Error!form.Function {
    var viewer: ?facts.Viewer = if (known) |table| try facts.Viewer.over(scratch, f, table) else null;
    const source: Source = .{ .module = module, .f = f, .known = known, .viewer = &viewer };
    var params: std.ArrayList(form.Type) = .empty;
    for (f.signature.params) |ty| try params.append(a, typeOf(module, ty));
    const internal = f.signature.linkage == .internal;
    var function: form.Function = .{ .header = .{ .name = f.name, .internal = internal, .address_taken = taken, .params = params.items, .ret = typeOf(module, f.signature.ret) } };
    function.pre = try constants(a, source);
    function.boundary = try boundary(a, source, internal and !taken);
    var blocks: std.ArrayList(form.Block) = .empty;
    var sites: std.ArrayList(form.Site) = .empty;
    for (f.blocks.items, 0..) |_, b| try blocks.append(a, try describeBlock(a, source, @intCast(b), &sites));
    function.blocks = blocks.items;
    function.aux = try auxiliary(a, source);
    function.aux.sites = sites.items;
    return function;
}

/// The constants and parameters, which live outside every block.
fn constants(a: Allocator, source: Source) Allocator.Error![]const form.Inst {
    var out: std.ArrayList(form.Inst) = .empty;
    // A comparison the facts folded is an `iconst` inside its block: it is listed there, not here.
    const placed = try a.alloc(bool, source.f.insts.items.len);
    @memset(placed, false);
    for (source.f.blocks.items) |block| for (block.insts.items) |ref| {
        placed[ref.index()] = true;
    };
    for (source.f.insts.items, 0..) |inst, index| {
        if (!inst.op.isConstant() or placed[index]) continue;
        try out.append(a, try describeInst(a, source, @fromBackingInt(@intCast(index))));
    }
    return out.items;
}

/// What the function states about its parameters and what it returns. Parameter intervals are stated only for a function
/// nothing outside the module can call.
fn boundary(a: Allocator, source: Source, closed: bool) Allocator.Error!form.Boundary {
    const f = source.f;
    var out: form.Boundary = .{};
    const table = source.known orelse return out;
    const params = try a.alloc(?form.Interval, f.signature.params.len);
    @memset(params, null);
    if (closed) for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .param and inst.data < params.len) params[@intCast(inst.data)] = interval(table.ranges[index]);
    };
    out.params = params;
    // The return line states what the validator's return rule (F6) reads: each `ret` operand's view at its block.
    const views: ?*facts.Viewer = if (source.viewer.*) |*prepared| prepared else null;
    out.returns = interval(facts.returnRangeWith(views, &table, f, .none));
    return out;
}

fn describeBlock(a: Allocator, source: Source, b: u32, sites: *std.ArrayList(form.Site)) Allocator.Error!form.Block {
    const f = source.f;
    const block = f.blocks.items[b];
    const preds = try a.alloc(u32, block.preds.items.len);
    for (preds, block.preds.items) |*slot, pred| slot.* = @intCast(pred.index());
    var phis: std.ArrayList(form.Phi) = .empty;
    var insts: std.ArrayList(form.Inst) = .empty;
    var term: form.Term = .unreachable_path;
    const refs = block.insts.items;
    for (refs, 0..) |ref, position| {
        const inst = f.inst(ref);
        if (position + 1 == refs.len and inst.op.terminates()) {
            term = terminator(f, inst);
            continue;
        }
        switch (inst.op) {
            .copy => {},
            .phi => try phis.append(a, try describePhi(a, source, ref)),
            else => {
                try insts.append(a, try describeInst(a, source, ref));
                if (inst.check == .proven) try sites.append(a, try describeSite(a, source, ref, @intCast(b)));
            },
        }
    }
    const dead = if (source.known) |table| !table.reachable[b] else false;
    return .{ .id = b, .dead = dead, .preds = preds, .phis = phis.items, .insts = insts.items, .term = term };
}

fn terminator(f: *const ir.Function, last: ir.Inst) form.Term {
    return switch (last.op) {
        .jump => .{ .jump = @intCast(last.data) },
        .branch => blk: {
            const targets = ir.unpackTargets(last.data);
            break :blk .{ .branch = .{ .condition = @intCast(f.resolve(last.a).index()), .then = @intCast(targets.then.index()), .otherwise = @intCast(targets.otherwise.index()) } };
        },
        .ret => .{ .ret = if (last.a == .none) null else @intCast(f.resolve(last.a).index()) },
        else => .unreachable_path,
    };
}

fn describePhi(a: Allocator, source: Source, ref: ir.Ref) Allocator.Error!form.Phi {
    const f = source.f;
    const inst = f.inst(ref);
    const operands = f.operands(inst.data);
    const edges = try a.alloc(form.Edge, operands.len);
    const block = blockOf(f, ref);
    const preds = f.blocks.items[block].preds.items;
    for (edges, operands, 0..) |*edge, operand, k| edge.* = .{ .block = if (k < preds.len) @intCast(preds[k].index()) else 0, .value = @intCast(f.resolve(operand).index()) };
    return .{ .value = @intCast(ref.index()), .ty = typeOf(source.module, inst.ty), .edges = edges, .range = rangeOf(source, ref) };
}

/// The block holding `ref` (a phi is always in one).
fn blockOf(f: *const ir.Function, ref: ir.Ref) usize {
    for (f.blocks.items, 0..) |block, b| for (block.insts.items) |candidate| {
        if (candidate == ref) return b;
    };
    return 0;
}

/// The stated interval of an integer or boolean value.
fn rangeOf(source: Source, ref: ir.Ref) ?form.Interval {
    const table = source.known orelse return null;
    if (!typeOf(source.module, source.f.inst(ref).ty).isInteger()) return null;
    return interval(table.ranges[ref.index()]);
}

fn describeInst(a: Allocator, source: Source, ref: ir.Ref) Allocator.Error!form.Inst {
    const f = source.f;
    const inst = f.inst(ref);
    var out: form.Inst = .{
        .value = @intCast(ref.index()),
        .op = inst.op,
        .ty = typeOf(source.module, inst.ty),
        .check = inst.check,
        .range = rangeOf(source, ref),
    };
    if (inst.op == .call) {
        out.operands.a = @intCast(inst.a.index());
    } else if (inst.a != .none and !inst.op.isConstant()) {
        out.operands.a = @intCast(f.resolve(inst.a).index());
    }
    if (inst.b != .none and inst.op != .call and !inst.op.isConstant()) out.operands.b = @intCast(f.resolve(inst.b).index());
    if (inst.op.hasExtra()) {
        const extra = f.operands(inst.data);
        const resolved = try a.alloc(u32, extra.len);
        for (resolved, extra) |*slot, operand| slot.* = if (operand == .none) std.math.maxInt(u32) else @intCast(f.resolve(operand).index());
        out.operands.x = resolved;
    } else out.immediates.imm = inst.data;
    if ((inst.op == .array_get or inst.op == .array_set) and inst.a != .none) {
        const array = f.inst(f.resolve(inst.a)).ty;
        if (array.isCompound() and source.module.kind(array) == .array) out.immediates.aux = source.module.compound(array).array.n;
    }
    return out;
}

/// The viewed intervals the check of `ref` read (design §10, Sites).
fn describeSite(a: Allocator, source: Source, ref: ir.Ref, b: u32) Allocator.Error!form.Site {
    const f = source.f;
    const inst = f.inst(ref);
    const block: ir.BlockId = @fromBackingInt(b);
    var parts: std.ArrayList(?form.Interval) = .empty;
    if (source.viewer.*) |*viewer| switch (inst.op) {
        .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem => {
            try parts.append(a, interval(viewer.range(inst.a, block)));
            try parts.append(a, interval(viewer.range(inst.b, block)));
        },
        .neg, .convert => try parts.append(a, interval(viewer.range(inst.a, block))),
        .shift_left, .shift_right, .array_get, .array_set => try parts.append(a, interval(viewer.range(inst.b, block))),
        .list_get, .list_get_field, .list_set => {
            try parts.append(a, interval(viewer.range(inst.b, block)));
            try parts.append(a, interval(viewer.listLen(inst.a)));
        },
        .list_pop => try parts.append(a, interval(viewer.listLen(inst.a))),
        else => {},
    };
    return .{ .value = @intCast(ref.index()), .parts = parts.items };
}

/// Which values appear in the description: the constants and parameters, and the phis and instructions of its blocks.
fn printedValues(a: Allocator, f: *const ir.Function) Allocator.Error![]bool {
    const out = try a.alloc(bool, f.insts.items.len);
    @memset(out, false);
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op.isConstant()) out[index] = true;
    }
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        if (f.inst(ref).op != .copy) out[ref.index()] = true;
    };
    return out;
}

/// The builder's loop records, the list facts and the length bounds.
fn auxiliary(a: Allocator, source: Source) Allocator.Error!form.Aux {
    const f = source.f;
    var out: form.Aux = .{};
    var loops: std.ArrayList(form.Loop) = .empty;
    for (f.loops.items) |loop| try loops.append(a, .{ .header = @intCast(loop.header.index()), .body = @intCast(loop.body.index()), .latch = @intCast(loop.latch.index()), .exit = @intCast(loop.exit.index()) });
    out.loops = loops.items;
    const table = source.known orelse return out;
    const printed = try printedValues(a, f);
    var lists: std.ArrayList(form.ListFact) = .empty;
    var bounds: std.ArrayList(form.Bound) = .empty;
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .copy or !printed[index]) continue;
        const ty = typeOf(source.module, inst.ty);
        if (ty == .list) {
            const fact = table.aggregates.lists[index];
            if (fact.len != null or fact.elements != null or fact.length != .none or fact.pattern) {
                try lists.append(a, .{
                    .value = @intCast(index),
                    .len = interval(fact.len),
                    .elems = interval(fact.elements),
                    .length = if (fact.length == .none) null else @intCast(fact.length.index()),
                    .pattern = fact.pattern,
                });
            }
        }
        if (ty.isInteger() and index < table.bounds.len) {
            if (table.bounds[index]) |bound| if (bound.list != .none) try bounds.append(a, .{ .value = @intCast(index), .list = @intCast(bound.list.index()), .strict = bound.strict });
        }
    }
    out.lists = lists.items;
    out.bounds = bounds.items;
    return out;
}

const sample =
    \\func total(n: int) -> int:
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += i * 2
    \\    return acc
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, total(10))
    \\    return 0
    \\
;

test "the exporter lists every function in module order with the facts the passes kept" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal = @import("build.zig").Refusal{};
    var module = try @import("test_support.zig").buildSource(a, sample, &refusal);
    const result = try @import("test_support.zig").runPasses(a, &module, .trusted);
    const described = try describe(a, a, &module, .{ .known = result.known, .fields = result.emission.fields });
    var seen: ?form.Function = null;
    for (described.functions) |function| {
        if (std.mem.eql(u8, function.header.name, "total")) seen = function;
    }
    const total = seen.?;
    // `total(10)` is the only call: the parameter interval is the hull of what callers pass, and the return follows from the loop
    try std.testing.expectEqual(form.Interval{ .lo = 10, .hi = 10 }, total.boundary.params[0].?);
    try std.testing.expect(total.boundary.returns != null);
    try std.testing.expect(total.aux.loops.len == 1);
    try std.testing.expect(total.aux.sites.len >= 2);
}

test "an optimizing build's description prints, with a site for every proven check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal = @import("build.zig").Refusal{};
    var module = try @import("test_support.zig").buildSource(a, sample, &refusal);
    const result = try @import("test_support.zig").runPasses(a, &module, .trusted);
    const described = try describe(a, a, &module, .{ .known = result.known, .fields = result.emission.fields });
    var out: std.ArrayList(u8) = .empty;
    try @import("fact_text.zig").write(a, &out, described);
    try std.testing.expect(std.mem.startsWith(u8, out.items, "fact-certificate-v1\n"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, " proven ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\nsite %") != null);
}

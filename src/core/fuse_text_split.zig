//! Private whitespace-split loops borrow their dictionary lookup keys from the source.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const views = @import("fuse_slice_key.zig");

const Candidate = struct {
    loop: ir.Loop,
    split: ir.Ref,
    length: ir.Ref,
    element: ir.Ref,
    counter: ir.Ref,
    next: ir.Ref,
    start_slot: u1,
};

/// Fuse private split iterations whose words are only dictionary lookup or insertion keys.
pub fn run(arena: std.mem.Allocator, module: *ir.Module) std.mem.Allocator.Error!void {
    const count = module.functions.items.len;
    for (0..count) |index| {
        // Adding runtime declarations may move the module's function array.
        var function = module.functions.items[index];
        if (function.signature.linkage != .internal) continue;
        for (function.loops.items) |loop| {
            const graph = try facts.shape(arena, &function);
            const candidate = find(&function, module, loop, graph) orelse continue;
            const inputs = function.operands(function.inst(candidate.split).data);
            var unstable = false;
            for (inputs) |input| {
                if (try views.updated(arena, &function, module, function.resolve(input))) unstable = true;
            }
            if (unstable) continue;
            try rewrite(arena, &function, module, candidate);
        }
        module.functions.items[index] = function;
    }
}

fn find(f: *const ir.Function, module: *const ir.Module, loop: ir.Loop, graph: facts.Shape) ?Candidate {
    const preds = f.blocks.items[loop.header.index()].preds.items;
    if (preds.len != 2) return null;
    for (f.blocks.items[loop.header.index()].insts.items) |ref| {
        const phi = f.inst(ref);
        if (phi.op != .phi or phi.ty != .i64) continue;
        const args = f.operands(phi.data);
        if (args.len != 2) continue;
        for (args, 0..) |arg, slot| {
            const initial = f.inst(f.resolve(arg));
            const next = f.resolve(args[1 - slot]);
            if (initial.op != .iconst or initial.data != 0 or preds[1 - slot] != loop.latch) continue;
            if (!increment(f, next, ref)) continue;
            if (candidateFor(f, module, .{ .loop = loop, .split = .none, .length = .none, .element = .none, .counter = ref, .next = next, .start_slot = @intCast(slot) }, graph)) |candidate| return candidate;
        }
    }
    return null;
}

fn increment(f: *const ir.Function, ref: ir.Ref, counter: ir.Ref) bool {
    const inst = f.inst(ref);
    if (inst.op != .add or f.resolve(inst.a) != counter) return false;
    const step = f.inst(f.resolve(inst.b));
    return step.op == .iconst and step.data == 1;
}

fn candidateFor(f: *const ir.Function, module: *const ir.Module, seed: Candidate, graph: facts.Shape) ?Candidate {
    var out = seed;
    var condition: ir.Ref = .none;
    var bound: ir.Ref = .none;
    for (f.blocks.items[out.loop.header.index()].insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op != .cmp or inst.data != @backingInt(ir.Predicate.lt) or f.resolve(inst.a) != out.counter) continue;
        bound = f.resolve(inst.b);
        const convert = f.inst(bound);
        if (convert.op != .convert or convert.ty != .i64) continue;
        out.length = f.resolve(convert.a);
        const length = f.inst(out.length);
        if (length.op != .list_len) continue;
        out.split = f.resolve(length.a);
        if (!splitCall(f, module, out.split)) continue;
        condition = ref;
        break;
    }
    if (condition == .none or graph.block_of[out.split.index()] != f.blocks.items[out.loop.header.index()].preds.items[out.start_slot]) return null;
    const header = f.blocks.items[out.loop.header.index()].insts.items;
    const branch = f.inst(header[header.len - 1]);
    if (branch.op != .branch or f.resolve(branch.a) != condition) return null;
    const targets = ir.unpackTargets(branch.data);
    if (targets.then != out.loop.body or targets.otherwise != out.loop.exit) return null;
    out.element = privateElement(f, out.split, out.length, out.counter) orelse return null;
    const block = graph.block_of[out.element.index()] orelse return null;
    if (!dominates(graph, block, out.loop.latch)) return null;
    if (!onlyUses(f, out.counter, &.{ condition, out.element, out.next })) return null;
    if (!onlyUses(f, out.length, &.{bound}) or !onlyUses(f, bound, &.{condition})) return null;
    if (whitespace(f, module, out.split) and !keyUses(f, module, out.element, 0)) return null;
    return out;
}

fn splitCall(f: *const ir.Function, module: *const ir.Module, ref: ir.Ref) bool {
    const inst = f.inst(ref);
    if (inst.op != .call or inst.a.index() >= module.functions.items.len or f.operands(inst.data).len == 0) return false;
    const target = module.functions.items[inst.a.index()];
    if (target.signature.linkage == .internal or target.signature.owned != 0 or target.signature.views != 0) return false;
    const explicit = std.mem.eql(u8, target.name, "myl_core_str_split");
    if (!explicit and target.signature.linkage != .runtime_c) return false;
    if (!explicit and !std.mem.eql(u8, target.name, "myl_core_str_split_whitespace")) return false;
    return std.mem.eql(ir.Type, target.signature.params, if (explicit) &.{ .str, .str } else &.{.str}) and module.kind(target.signature.ret) == .list and module.compound(target.signature.ret).list == .str;
}

fn whitespace(f: *const ir.Function, module: *const ir.Module, ref: ir.Ref) bool {
    return std.mem.eql(u8, module.functions.items[f.inst(ref).a.index()].name, "myl_core_str_split_whitespace");
}

fn privateElement(f: *const ir.Function, split: ir.Ref, length: ir.Ref, counter: ir.Ref) ?ir.Ref {
    var element: ir.Ref = .none;
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != split) continue;
            const ref: ir.Ref = @fromBackingInt(@intCast(index));
            if (ref == length and at == 0) continue;
            if (inst.op != .list_get or at != 0 or inst.ty != .str) return null;
            if (f.resolve(inst.b) != counter or element != .none) return null;
            element = ref;
        }
    }
    return if (element == .none) null else element;
}

fn onlyUses(f: *const ir.Function, value: ir.Ref, allowed: []const ir.Ref) bool {
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != value) continue;
            const user: ir.Ref = @fromBackingInt(@intCast(index));
            if (std.mem.indexOfScalar(ir.Ref, allowed, user) == null) return false;
        }
    }
    return true;
}

fn keyCopy(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.ty != .str or inst.a.index() >= module.functions.items.len or f.operands(inst.data).len != 1) return false;
    const target = module.functions.items[inst.a.index()];
    return target.signature.linkage == .runtime_c and target.signature.owned == 0 and target.signature.views == 0 and target.signature.consumes == 0 and
        target.signature.ret == .str and std.mem.eql(ir.Type, target.signature.params, &.{.str}) and
        std.mem.eql(u8, target.name, "myl_core_owned_octets_copy");
}

fn keyUses(f: *const ir.Function, module: *const ir.Module, element: ir.Ref, depth: u8) bool {
    // Bound recognition of explicit copy chains; deeper chains remain owned.
    if (depth == 16) return false;
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != element) continue;
            // An explicit independent copy may be deferred only when all its
            // uses are probes or insertions; insertion still materializes a key.
            if (keyCopy(f, module, inst) and keyUses(f, module, @fromBackingInt(@intCast(index)), depth + 1)) continue;
            const lookup_key = inst.op == .dict_find and at == 1;
            const insertion_key = inst.op == .dict_insert and at == 2;
            if (!lookup_key and !insertion_key) return false;
            const ty = f.inst(f.resolve(inst.a)).ty;
            if (module.kind(ty) != .dict or module.compound(ty).dict.key != .str) return false;
        }
    }
    return true;
}

fn dominates(graph: facts.Shape, parent: ir.BlockId, child: ir.BlockId) bool {
    var at: ?ir.BlockId = child;
    while (at) |block| {
        if (block == parent) return true;
        if (block.index() == 0) return false;
        at = graph.idom[block.index()];
    }
    return false;
}

fn runtime(arena: std.mem.Allocator, module: *ir.Module, symbol: []const u8) std.mem.Allocator.Error!ir.Ref {
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .runtime_c or function.signature.ret != .i64) continue;
        if (!std.mem.eql(ir.Type, function.signature.params, &.{ .str, .i64 })) continue;
        if (std.mem.eql(u8, function.name, symbol)) return @fromBackingInt(@intCast(index));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(arena, .{ .name = symbol, .signature = .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .runtime_c } });
    return ref;
}

fn extra(arena: std.mem.Allocator, f: *ir.Function, args: []const ir.Ref) std.mem.Allocator.Error!u64 {
    const start: u32 = @intCast(f.extra.items.len);
    try f.extra.appendSlice(arena, args);
    return (ir.ExtraSlice{ .start = start, .len = @intCast(args.len) }).pack();
}

fn append(arena: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, inst);
    return ref;
}

fn before(arena: std.mem.Allocator, f: *ir.Function, ref: ir.Ref, added: []const ir.Ref) std.mem.Allocator.Error!void {
    for (f.blocks.items) |*block| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |at| {
            try block.insts.insertSlice(arena, at, added);
            return;
        }
    }
    unreachable;
}

fn rewrite(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, candidate: Candidate) std.mem.Allocator.Error!void {
    if (!whitespace(f, module, candidate.split)) return explicitRewrite(arena, f, module, candidate);
    deferKeyCopies(f, module, candidate.element);
    const list_type = f.inst(candidate.split).ty;
    const source = f.operands(f.inst(candidate.split).data)[0];
    const start_fn = try runtime(arena, module, "myl_core_split_ws_start");
    const end_fn = try runtime(arena, module, "myl_core_split_ws_end");
    const zero = try append(arena, f, .{ .op = .iconst, .ty = .i64 });
    f.insts.items[candidate.split.index()] = .{ .op = .call, .ty = .i64, .a = start_fn, .data = try extra(arena, f, &.{ source, zero }) };
    const phi = f.inst(candidate.counter);
    const phi_args = ir.ExtraSlice.unpack(phi.data);
    f.extra.items[phi_args.start + candidate.start_slot] = candidate.split;
    f.insts.items[candidate.length.index()] = .{ .op = .str_len, .ty = .u64, .a = source };
    const end = try append(arena, f, .{ .op = .call, .ty = .i64, .a = end_fn, .data = try extra(arena, f, &.{ source, candidate.counter }) });
    const offset = try append(arena, f, .{ .op = .convert, .ty = .u64, .a = candidate.counter, .check = .exact });
    const width = try append(arena, f, .{ .op = .sub, .ty = .i64, .a = end, .b = candidate.counter, .check = .exact });
    const length = try append(arena, f, .{ .op = .convert, .ty = .u64, .a = width, .check = .exact });
    try before(arena, f, candidate.element, &.{ end, offset, width, length });
    f.insts.items[candidate.element.index()] = .{ .op = .str_view_of, .ty = .str_view, .a = source, .b = offset, .data = try extra(arena, f, &.{length}) };
    f.insts.items[candidate.next.index()] = .{ .op = .call, .ty = .i64, .a = start_fn, .data = try extra(arena, f, &.{ source, end }) };
    const empty = try append(arena, f, .{ .op = .undef, .ty = list_type });
    for (f.insts.items) |*inst| {
        if (inst.op == .copy and f.resolve(inst.a) == candidate.split) {
            inst.a = empty;
        }
    }
    try materializeInsertions(arena, f, candidate.element);
}

fn deferKeyCopies(f: *ir.Function, module: *const ir.Module, element: ir.Ref) void {
    // Repeat to cover nested explicit copies regardless of instruction order.
    var changed = true;
    while (changed) {
        changed = false;
        for (f.insts.items) |*inst| {
            if (!keyCopy(f, module, inst.*) or f.resolve(f.operands(inst.data)[0]) != element) continue;
            inst.* = .{ .op = .copy, .ty = .str_view, .a = element, .span = inst.span };
            changed = true;
        }
    }
}

fn materializeInsertions(arena: std.mem.Allocator, f: *ir.Function, element: ir.Ref) std.mem.Allocator.Error!void {
    const count = f.insts.items.len;
    for (0..count) |index| {
        const inst = f.insts.items[index];
        if (inst.op == .copy and f.resolve(inst.a) == element) {
            f.insts.items[index].ty = .str_view;
            continue;
        }
        if (inst.op != .dict_insert or f.resolve(f.operands(inst.data)[0]) != element) continue;
        const value = f.operands(inst.data)[1];
        const key = try append(arena, f, .{ .op = .str_from_view, .ty = .str, .a = element, .span = inst.span });
        try before(arena, f, @fromBackingInt(@intCast(index)), &.{key});
        f.insts.items[index].data = try extra(arena, f, &.{ key, value });
    }
}

fn splitRuntime(arena: std.mem.Allocator, module: *ir.Module, symbol: []const u8) std.mem.Allocator.Error!ir.Ref {
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, symbol)) return @fromBackingInt(@intCast(index));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(arena, .{ .name = symbol, .signature = .{ .params = &.{ .str, .str, .i64 }, .ret = .i64, .linkage = .runtime_c } });
    return ref;
}

fn explicitRewrite(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, candidate: Candidate) std.mem.Allocator.Error!void {
    const list_type = f.inst(candidate.split).ty;
    const split_args = f.operands(f.inst(candidate.split).data);
    const source = split_args[0];
    const separator = split_args[1];
    const start_fn = try splitRuntime(arena, module, "myl_core_split_start");
    const end_fn = try splitRuntime(arena, module, "myl_core_split_end");
    const next_fn = try splitRuntime(arena, module, "myl_core_split_next");
    const readable = views.onlyReads(f, module, candidate.element);
    const zero = try append(arena, f, .{ .op = .iconst, .ty = .i64 });
    f.insts.items[candidate.split.index()] = .{ .op = .call, .ty = .i64, .a = start_fn, .data = try extra(arena, f, &.{ source, separator, zero }) };
    const phi = f.inst(candidate.counter);
    const phi_args = ir.ExtraSlice.unpack(phi.data);
    f.extra.items[phi_args.start + candidate.start_slot] = candidate.split;
    f.insts.items[candidate.length.index()] = .{ .op = .iconst, .ty = .u64 };
    for (f.blocks.items[candidate.loop.header.index()].insts.items) |ref| {
        const inst = &f.insts.items[ref.index()];
        if (inst.op == .cmp and f.resolve(inst.a) == candidate.counter) inst.data = @backingInt(ir.Predicate.ge);
    }
    const end = try append(arena, f, .{ .op = .call, .ty = .i64, .a = end_fn, .data = try extra(arena, f, &.{ source, separator, candidate.counter }) });
    const offset = try append(arena, f, .{ .op = .convert, .ty = .u64, .a = candidate.counter, .check = .exact });
    const width = try append(arena, f, .{ .op = .sub, .ty = .i64, .a = end, .b = candidate.counter, .check = .exact });
    const length = try append(arena, f, .{ .op = .convert, .ty = .u64, .a = width, .check = .exact });
    try before(arena, f, candidate.element, &.{ end, offset, width, length });
    const view: ir.Inst = .{ .op = .str_view_of, .ty = .str_view, .a = source, .b = offset, .data = try extra(arena, f, &.{length}), .span = f.inst(candidate.element).span };
    if (readable) {
        f.insts.items[candidate.element.index()] = view;
        try views.rewriteUses(arena, f, module, candidate.element);
    } else {
        const borrowed = try append(arena, f, view);
        try before(arena, f, candidate.element, &.{borrowed});
        f.insts.items[candidate.element.index()] = .{ .op = .str_from_view, .ty = .str, .a = borrowed, .span = view.span };
    }
    f.insts.items[candidate.next.index()] = .{ .op = .call, .ty = .i64, .a = next_fn, .data = try extra(arena, f, &.{ source, separator, end }) };
    const empty = try append(arena, f, .{ .op = .undef, .ty = list_type });
    for (f.insts.items) |*inst| {
        if (inst.op == .copy and f.resolve(inst.a) == candidate.split) inst.a = empty;
    }
}

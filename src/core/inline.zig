//! Release builds inline small leaf functions before the fact pass, so the facts
//! (and the vector lowering) see through helpers such as `affine_a(x) = x*3+7`.
//!
//! A callee qualifies when it is internal, has exactly one block, ends in
//! `ret value`, and contains no call, print, phi or error trace. Trace-bearing
//! functions retain their specialized names and sites until LLVM inlining.
//! Other instructions are cloned
//! into the caller in front of the call, its parameters replaced by the call's
//! arguments, and the call becomes a forwarding `copy` of the returned value.
//! A checked body is copied only with proof that its checks cannot fail; unsafe
//! or unproved bodies retain their source frames until LLVM inlining.
const std = @import("std");
const demand_ir = @import("demand_ir.zig");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const proof = @import("inline_proof.zig");
const cfg = @import("inline_cfg.zig");
const origins = @import("inline_origins.zig");

/// Inlining only allocates.
pub const Error = demand_ir.Error;

/// Inline every qualifying call in `module`'s internal functions; returns how many.
pub fn inlineLeaves(arena: std.mem.Allocator, module: *ir.Module, provenance: *origins.Table) Error!u32 {
    return inlineLeavesCounted(arena, module, provenance, null);
}

/// The same inlining, also recording each physical caller's successful expansions.
pub fn inlineLeavesCounted(arena: std.mem.Allocator, module: *ir.Module, provenance: *origins.Table, counts: ?[]u32) Error!u32 {
    return inlineLeavesCountedWithScratch(arena, arena, module, provenance, counts);
}

/// Reclaim proof facts after each caller while retaining cloned IR and provenance.
pub fn inlineLeavesCountedWithScratch(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, provenance: *origins.Table, counts: ?[]u32) Error!u32 {
    const leaves = try withParametersCountedWithScratch(arena, backing, module, &.{}, provenance, counts);
    const helpers = try inlineCfg(arena, module, provenance, counts);
    return leaves + helpers;
}

/// Apply bounded consuming CFG cloning once, before the caller parameter pass.
fn inlineCfg(arena: std.mem.Allocator, module: *ir.Module, provenance: *origins.Table, counts: ?[]u32) Error!u32 {
    var count: u32 = 0;
    for (module.functions.items, 0..) |caller, index| {
        if (caller.signature.linkage != .internal) continue;
        const changed = try cfgCaller(arena, module, @intCast(index), provenance);
        count += changed;
        if (counts) |local| local[index] += changed;
    }
    return count;
}

/// Apply the existing CFG round to one caller in module mutation order.
pub fn cfgCaller(arena: std.mem.Allocator, module: *ir.Module, index: u32, provenance: *origins.Table) Error!u32 {
    return cfgCallerDemand(arena, module, index, provenance, null);
}

/// Resolve a callee only when an uncached CFG inline trial examines its body.
pub fn cfgCallerDemand(arena: std.mem.Allocator, module: *ir.Module, index: u32, provenance: *origins.Table, demand: ?*demand_ir.Context) Error!u32 {
    const caller = &module.functions.items[index];
    var count: u32 = 0;
    var b: usize = 0;
    while (b < caller.blocks.items.len) : (b += 1) {
        var at: usize = 0;
        while (at < caller.blocks.items[b].insts.items.len) : (at += 1) {
            const ref = caller.blocks.items[b].insts.items[at];
            const call = caller.inst(ref);
            if (call.op != .call or call.a.index() == index) continue;
            if (demand) |handles| try handles.ensure(@intCast(call.a.index()));
            const callee = &module.functions.items[call.a.index()];
            if (!cfg.qualifies(callee)) continue;
            var clone = try provenance.prepare(arena, .{ .caller = @intCast(index), .callee = @intCast(call.a.index()), .block = @intCast(b), .ref = ref, .span = call.span }, callee) orelse continue;
            try cfg.splice(arena, caller, callee, b, at, &clone);
            count += 1;
            break;
        }
    }
    return count;
}

/// Revisit leaves and attribute successful expansions to their physical caller.
pub fn withParametersCounted(arena: std.mem.Allocator, module: *ir.Module, parameters: []const []const ?facts.Interval, provenance: *origins.Table, counts: ?[]u32) Error!u32 {
    return withParametersCountedWithScratch(arena, arena, module, parameters, provenance, counts);
}

/// A reusable proof arena releases every caller's dense analysis before the next.
pub fn withParametersCountedWithScratch(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, parameters: []const []const ?facts.Interval, provenance: *origins.Table, counts: ?[]u32) Error!u32 {
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    var count: u32 = 0;
    for (module.functions.items, 0..) |caller, index| {
        if (caller.signature.linkage != .internal) continue;
        const changed = try leafCallerWithScratch(arena, work.allocator(), module, @intCast(index), if (index < parameters.len) parameters[index] else &.{}, provenance);
        count += changed;
        if (counts) |local| local[index] += changed;
        _ = work.reset(.retain_capacity);
    }
    return count;
}

/// Apply the existing leaf round to one caller in module mutation order.
pub fn leafCaller(arena: std.mem.Allocator, module: *ir.Module, index: u32, parameters: []const ?facts.Interval, provenance: *origins.Table) Error!u32 {
    return leafCallerWithScratch(arena, arena, module, index, parameters, provenance);
}

/// Scratch facts and trial copies never escape; only cloned IR uses `arena`.
pub fn leafCallerWithScratch(arena: std.mem.Allocator, scratch: std.mem.Allocator, module: *ir.Module, index: u32, parameters: []const ?facts.Interval, provenance: *origins.Table) Error!u32 {
    return leafCallerDemand(arena, scratch, module, index, parameters, .{ .provenance = provenance });
}

/// Shared source ancestry and optional lowering handles for an inline trial.
pub const DemandState = struct { provenance: *origins.Table, raw: ?*demand_ir.Context = null };

/// Resolve only the callees reached by this actual leaf inline trial.
pub fn leafCallerDemand(arena: std.mem.Allocator, scratch: std.mem.Allocator, module: *ir.Module, index: u32, parameters: []const ?facts.Interval, state: DemandState) Error!u32 {
    const provenance = state.provenance;
    const demand = state.raw;
    const caller = &module.functions.items[index];
    // A child arena reuses its largest trial; the caller's known facts remain
    // on parent scratch until this invocation finishes.
    var trials = std.heap.ArenaAllocator.init(scratch);
    defer trials.deinit();
    var count: u32 = 0;
    var known: ?facts.Facts = null;
    for (caller.blocks.items, 0..) |*block, b| {
        var at: usize = 0;
        while (at < block.insts.items.len) : (at += 1) {
            const ref = block.insts.items[at];
            var call = caller.insts.items[ref.index()];
            @import("build_fn.zig").directTarget(caller, &call);
            caller.insts.items[ref.index()] = call;
            if (call.op != .call or call.a.index() == index) continue;
            if (demand) |handles| try handles.ensure(@intCast(call.a.index()));
            const callee = &module.functions.items[call.a.index()];
            const result = leaf(callee) orelse continue;
            if (proof.needsProof(callee)) {
                if (known == null) known = try facts.analyze(scratch, caller, .{ .fold = false, .mark = false, .params = parameters });
                const safe = try proof.trapFree(trials.allocator(), caller, call, callee, known.?);
                _ = trials.reset(.retain_capacity);
                if (!safe) continue;
            }
            var clone = try provenance.prepare(arena, .{ .caller = @intCast(index), .callee = @intCast(call.a.index()), .block = @intCast(b), .ref = ref, .span = call.span }, callee) orelse continue;
            const cloned = try splice(arena, caller, callee, .{ .block = block, .at = at, .call = ref, .result = result }, &clone);
            at += cloned;
            count += 1;
        }
    }
    return count;
}

/// The returned value of a qualifying leaf, or null.
fn leaf(callee: *const ir.Function) ?ir.Ref {
    if (callee.signature.linkage != .internal or callee.blocks.items.len != 1 or callee.signature.ret == .void) return null;
    const insts = callee.blocks.items[0].insts.items;
    if (insts.len == 0) return null;
    const last = callee.inst(insts[insts.len - 1]);
    if (last.op != .ret or last.a == .none) return null;
    for (insts[0 .. insts.len - 1]) |ref| switch (callee.inst(ref).op) {
        .call, .call_indirect, .print, .phi, .jump, .branch, .ret, .@"unreachable", .err_trace => return null,
        else => {},
    };
    return last.a;
}

/// Where one call is replaced.
const Site = struct { block: *ir.Block, at: usize, call: ir.Ref, result: ir.Ref };

/// Clone the callee's body into the caller before `site.at`; returns the number of instructions inserted.
fn splice(arena: std.mem.Allocator, caller: *ir.Function, callee: *const ir.Function, site: Site, clone: *origins.Clone) Error!usize {
    const arguments = caller.operands(caller.insts.items[site.call.index()].data);
    const map = try arena.alloc(ir.Ref, callee.insts.items.len);
    @memset(map, .none);
    // Parameters become the arguments; block-less constants are cloned on demand.
    for (callee.insts.items, 0..) |inst, i| {
        map[i] = switch (inst.op) {
            .param => arguments[@intCast(inst.data)],
            .iconst, .fconst, .undef, .str_const, .func_ref => try append(arena, caller, inst),
            else => .none,
        };
    }
    var inserted: std.ArrayList(ir.Ref) = .empty;
    const body = callee.blocks.items[0].insts.items;
    for (body[0 .. body.len - 1]) |old| {
        var inst = callee.inst(old);
        inst.a = remap(callee, map, inst.a);
        inst.b = remap(callee, map, inst.b);
        if (inst.op.hasExtra()) {
            // `record_make` and `list_set` carry operands in the callee's extra list.
            const start: u32 = @intCast(caller.extra.items.len);
            for (callee.operands(inst.data)) |operand| try caller.extra.append(arena, remap(callee, map, operand));
            inst.data = (ir.ExtraSlice{ .start = start, .len = @intCast(caller.extra.items.len - start) }).pack();
        }
        const ref = try append(arena, caller, inst);
        try clone.instruction(arena, 0, old, ref, true);
        map[old.index()] = ref;
        try inserted.append(arena, ref);
    }
    try site.block.insts.insertSlice(arena, site.at, inserted.items);
    caller.insts.items[site.call.index()] = .{ .op = .copy, .ty = caller.insts.items[site.call.index()].ty, .a = remap(callee, map, site.result) };
    return inserted.items.len;
}

fn remap(callee: *const ir.Function, map: []const ir.Ref, raw: ir.Ref) ir.Ref {
    if (raw == .none) return .none;
    return map[callee.resolve(raw).index()];
}

fn append(arena: std.mem.Allocator, function: *ir.Function, inst: ir.Inst) Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(function.insts.items.len));
    try function.insts.append(arena, inst);
    return ref;
}

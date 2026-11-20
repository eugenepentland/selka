//! Fault injection for fact certificates (docs/audits/ownership-certificates-plan-2026-10-26.md, C7.4): single-edit mutants of
//! a certificate that a sound checker must reject. Each class makes one kind of false claim the fact pass could make, and is
//! built so that the false claim cannot be accepted: a range narrower than what the rules derive, a site that does not imply
//! its check, a block that can execute stated dead. The checker's own derivation (`validate_facts.derivedOf`, `viewOf`,
//! `rowHolds`) says where a class applies; the rejection of every mutant by the Zig validator and, later, by the Lean checker
//! is the evidence that neither accepts a claim of that kind.
const std = @import("std");
const ir = @import("ir.zig");
const form = @import("fact_function.zig");
const validate = @import("validate_facts.zig");

const Allocator = std.mem.Allocator;
const Interval = form.Interval;

/// The kinds of false claim.
pub const Class = enum {
    /// A stated range one step narrower than what the rule of its instruction derives.
    narrow_range,
    /// An operand's stated range widened to its type's, so that the site of a proven check claims more than the operands give.
    widen_operand,
    /// A site stated without the branch refinement that made its check provable.
    drop_refinement,
    /// A `proven` check stated without a site.
    missing_site,
    /// A checked operation marked `proven` that its operand intervals do not justify.
    unjustified_proven,
    /// A constant stated to lie in an interval that excludes it.
    wrong_range,
    /// A loop phi's range one step narrower than every rule gives it, so that it does not survive a trip.
    loop_range,
    /// A block stated dead that an unconditional jump reaches.
    dead_block,
    /// A return interval one step narrower than what a `ret` returns.
    narrow_return,
};

/// One mutant: the whole module with one edit, and the function the edit is in.
pub const Mutant = struct {
    class: Class,
    function: usize,
    module: form.Module,
};

/// The mutants of one class.
pub const Mutants = std.ArrayList(Mutant);

/// How many candidate edits of one function a class tries before moving on.
const candidates_per_function: usize = 64;

/// What to make: mutants of `class`, edited only in the functions `accepted` marks, at most `limit` of them.
pub const Request = struct { class: Class, accepted: []const bool, limit: usize };

/// Append the mutants `request` asks for to `out`. `keep` holds the mutants, `backing` the checker's work.
pub fn mutate(keep: Allocator, backing: Allocator, module: form.Module, request: Request, out: *Mutants) Allocator.Error!void {
    const class = request.class;
    const accepted = request.accepted;
    const limit = request.limit;
    var made: usize = 0;
    for (module.functions, 0..) |function, index| {
        if (made >= limit) return;
        if (!accepted[index] or function.blocks.len == 0) continue;
        var tried: usize = 0;
        var cursor: Cursor = .{};
        while (made < limit and tried < candidates_per_function) : (tried += 1) {
            const edited = try attempt(keep, backing, class, module, index, &cursor) orelse break;
            if (edited.keep) {
                try out.append(keep, .{ .class = class, .function = index, .module = edited.module });
                made += 1;
            }
        }
    }
}

/// Where the next candidate of a class is: a flat position over the function's phis, then instructions, block by block.
const Cursor = struct { position: usize = 0 };

const Attempt = struct { module: form.Module, keep: bool };

/// A place an edit can go: block position, then (phi or inst) position, or the constants.
const Place = struct { block: ?usize, phi: bool, index: usize };

/// The next place in `function` after `cursor`, or null at the end.
fn nextPlace(function: form.Function, cursor: *Cursor) ?Place {
    var skip = cursor.position;
    for (function.pre, 0..) |_, k| {
        if (skip == 0) {
            cursor.position += 1;
            return .{ .block = null, .phi = false, .index = k };
        }
        skip -= 1;
    }
    for (function.blocks, 0..) |block, b| {
        if (block.dead) continue;
        for (block.phis, 0..) |_, k| {
            if (skip == 0) {
                cursor.position += 1;
                return .{ .block = b, .phi = true, .index = k };
            }
            skip -= 1;
        }
        for (block.insts, 0..) |_, k| {
            if (skip == 0) {
                cursor.position += 1;
                return .{ .block = b, .phi = false, .index = k };
            }
            skip -= 1;
        }
    }
    return null;
}

fn attempt(keep: Allocator, backing: Allocator, class: Class, module: form.Module, index: usize, cursor: *Cursor) Allocator.Error!?Attempt {
    const original = module.functions[index];
    const place = nextPlace(original, cursor) orelse return null;
    const none: Attempt = .{ .module = module, .keep = false };
    switch (class) {
        .narrow_range, .loop_range => {
            const stated = rangeAt(original, place) orelse return none;
            if (class == .loop_range and !(place.phi and isLoopHeader(original, place.block.?))) return none;
            const value = valueAt(original, place);
            const derived = (try validate.derivedOf(keep, backing, module, index, value)) orelse return none;
            if (derived.hi <= derived.lo or !derived.within(stated)) return none;
            var function = try clone(keep, original);
            setRange(&function, place, .{ .lo = derived.lo, .hi = derived.hi - 1 });
            return .{ .module = try replace(keep, module, index, function), .keep = true };
        },
        .wrong_range => {
            const inst = instAt(original, place) orelse return none;
            if (inst.op != .iconst or inst.ty == .bool) return none;
            const limits = inst.ty.range() orelse return none;
            const value: i128 = if (inst.ty == .u64) inst.immediates.imm else @as(i64, @bitCast(inst.immediates.imm));
            const wrong: i128 = if (value + 1 <= limits.hi) value + 1 else value - 1;
            if (wrong < limits.lo) return none;
            var function = try clone(keep, original);
            setRange(&function, place, .{ .lo = wrong, .hi = wrong });
            return .{ .module = try replace(keep, module, index, function), .keep = true };
        },
        .dead_block => {
            const b = place.block orelse return none;
            if (b == 0 or !firstOfBlock(original, place)) return none;
            for (original.blocks[b].preds) |pred| {
                if (original.blocks[pred].dead or std.meta.activeTag(original.blocks[pred].term) != .jump) continue;
                const function = try clone(keep, original);
                const blocks = @constCast(function.blocks);
                blocks[b].dead = true;
                return .{ .module = try replace(keep, module, index, function), .keep = true };
            }
            return none;
        },
        .narrow_return => {
            const claim = original.boundary.returns orelse return none;
            if (place.block == null or !firstOfBlock(original, place)) return none;
            const block = original.blocks[place.block.?];
            const value = switch (block.term) {
                .ret => |v| v orelse return none,
                else => return none,
            };
            const seen = (try validate.viewOf(keep, backing, module, index, value, @intCast(place.block.?))) orelse return none;
            if (seen.hi <= seen.lo or !seen.within(claim)) return none;
            var function = try clone(keep, original);
            function.boundary.returns = .{ .lo = seen.lo, .hi = seen.hi - 1 };
            return .{ .module = try replace(keep, module, index, function), .keep = true };
        },
        .missing_site, .drop_refinement, .widen_operand, .unjustified_proven => {
            const edited = try siteClass(keep, backing, class, module, index, place);
            return edited;
        },
    }
}

/// The classes that edit a `proven` check or its site.
fn siteClass(keep: Allocator, backing: Allocator, class: Class, module: form.Module, index: usize, place: Place) Allocator.Error!?Attempt {
    const original = module.functions[index];
    const none: Attempt = .{ .module = module, .keep = false };
    const b = place.block orelse return none;
    if (place.phi) return none;
    const inst = original.blocks[b].insts[place.index];
    const site_at = siteIndex(original, inst.value);
    switch (class) {
        .missing_site => {
            if (inst.check != .proven or !validate.hasRow(inst.op)) return none;
            const at = site_at orelse return none;
            var function = try clone(keep, original);
            function.aux.sites = try removeAt(keep, form.Site, function.aux.sites, at);
            return .{ .module = try replace(keep, module, index, function), .keep = true };
        },
        .unjustified_proven => {
            if (inst.check != .exact or site_at != null) return none;
            if (inst.op != .add and inst.op != .sub and inst.op != .mul) return none;
            const x = (try validate.viewOf(keep, backing, module, index, inst.operands.a orelse return none, @intCast(b))) orelse return none;
            const y = (try validate.viewOf(keep, backing, module, index, inst.operands.b orelse return none, @intCast(b))) orelse return none;
            var marked = inst;
            marked.check = .proven;
            if (validate.rowHolds(marked, &[_]?Interval{ x, y }) orelse true) return none;
            var function = try clone(keep, original);
            @constCast(function.blocks[b].insts)[place.index].check = .proven;
            const parts = try keep.dupe(?Interval, &.{ x, y });
            const sites = try keep.alloc(form.Site, function.aux.sites.len + 1);
            @memcpy(sites[0..function.aux.sites.len], function.aux.sites);
            sites[function.aux.sites.len] = .{ .value = inst.value, .parts = parts };
            function.aux.sites = sites;
            return .{ .module = try replace(keep, module, index, function), .keep = true };
        },
        .drop_refinement => {
            if (inst.check != .proven) return none;
            const at = site_at orelse return none;
            const site = original.aux.sites[at];
            if (!validate.hasRow(inst.op) or site.parts.len == 0) return none;
            // A list access `len` does not justify is reported unchecked (other reasons exist), not rejected.
            switch (inst.op) {
                .list_get, .list_get_field, .list_set, .list_pop => return none,
                else => {},
            }
            for (site.parts, 0..) |part, k| {
                const claim = part orelse continue;
                const operand = operandValue(inst, k) orelse continue;
                const wide = unrefined(original, operand) orelse continue;
                if (std.meta.eql(wide, claim) or !claim.within(wide)) continue;
                const widened = try keep.dupe(?Interval, site.parts);
                widened[k] = wide;
                if (validate.rowHolds(inst, widened) orelse true) continue;
                const function = try clone(keep, original);
                @constCast(function.aux.sites)[at].parts = widened;
                return .{ .module = try replace(keep, module, index, function), .keep = true };
            }
            return none;
        },
        .widen_operand => {
            if (inst.check != .proven or (inst.op != .add and inst.op != .sub and inst.op != .mul)) return none;
            const at = site_at orelse return none;
            const site = original.aux.sites[at];
            for (0..2) |k| {
                const operand = operandValue(inst, k) orelse continue;
                const claim = (if (k < site.parts.len) site.parts[k] else null) orelse continue;
                const where = findDef(original, operand) orelse continue;
                if (where.constant or where.range == null) continue;
                var function = try clone(keep, original);
                clearRange(&function, operand);
                const mutated = try replace(keep, module, index, function);
                const view = (try validate.viewOf(keep, backing, mutated, index, operand, @intCast(b))) orelse continue;
                if (view.within(claim)) continue;
                return .{ .module = mutated, .keep = true };
            }
            return none;
        },
        else => unreachable,
    }
}

// ---- reading and editing the form -----------------------------------------------------------------------------------------

/// Whether `place` is the first phi or instruction of its block.
fn firstOfBlock(function: form.Function, place: Place) bool {
    const b = place.block orelse return false;
    if (place.phi) return place.index == 0;
    return place.index == 0 and function.blocks[b].phis.len == 0;
}

fn instAt(function: form.Function, place: Place) ?form.Inst {
    if (place.phi) return null;
    if (place.block) |b| return function.blocks[b].insts[place.index];
    return function.pre[place.index];
}

fn valueAt(function: form.Function, place: Place) u32 {
    if (place.phi) return function.blocks[place.block.?].phis[place.index].value;
    return instAt(function, place).?.value;
}

fn rangeAt(function: form.Function, place: Place) ?Interval {
    if (place.phi) return function.blocks[place.block.?].phis[place.index].range;
    return instAt(function, place).?.range;
}

fn setRange(function: *form.Function, place: Place, range: ?Interval) void {
    if (place.phi) {
        @constCast(function.blocks[place.block.?].phis)[place.index].range = range;
    } else if (place.block) |b| {
        @constCast(function.blocks[b].insts)[place.index].range = range;
    } else @constCast(function.pre)[place.index].range = range;
}

fn clearRange(function: *form.Function, value: u32) void {
    for (@constCast(function.pre)) |*inst| if (inst.value == value) {
        inst.range = null;
    };
    for (@constCast(function.blocks)) |*block| {
        for (@constCast(block.phis)) |*phi| if (phi.value == value) {
            phi.range = null;
        };
        for (@constCast(block.insts)) |*inst| if (inst.value == value) {
            inst.range = null;
        };
    }
}

fn isLoopHeader(function: form.Function, block: usize) bool {
    for (function.aux.loops) |loop| if (loop.header == block) return true;
    return false;
}

fn siteIndex(function: form.Function, value: u32) ?usize {
    for (function.aux.sites, 0..) |site, k| if (site.value == value) return k;
    return null;
}

/// The value operand `k` of the site of `inst` names, in the order of design §10 (Sites).
fn operandValue(inst: form.Inst, k: usize) ?u32 {
    return switch (inst.op) {
        .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem => if (k == 0) inst.operands.a else if (k == 1) inst.operands.b else null,
        .neg, .convert => if (k == 0) inst.operands.a else null,
        .shift_left, .shift_right, .array_get, .array_set, .list_get, .list_get_field, .list_set => if (k == 0) inst.operands.b else null,
        else => null,
    };
}

const Found = struct { range: ?Interval, constant: bool, ty: form.Type };

fn findDef(function: form.Function, value: u32) ?Found {
    for (function.pre) |inst| if (inst.value == value) return .{ .range = inst.range, .constant = inst.op == .iconst, .ty = inst.ty };
    for (function.blocks) |block| {
        for (block.phis) |phi| if (phi.value == value) return .{ .range = phi.range, .constant = false, .ty = phi.ty };
        for (block.insts) |inst| if (inst.value == value) return .{ .range = inst.range, .constant = inst.op == .iconst, .ty = inst.ty };
    }
    return null;
}

/// The interval of a value with no branch refinement: a constant's point, else its stated range, else its type's.
fn unrefined(function: form.Function, value: u32) ?Interval {
    const found = findDef(function, value) orelse return null;
    if (found.constant) {
        for (function.pre) |inst| if (inst.value == value) return Interval.point(constantOf(inst));
        for (function.blocks) |block| for (block.insts) |inst| if (inst.value == value) return Interval.point(constantOf(inst));
    }
    return found.range orelse found.ty.range();
}

fn constantOf(inst: form.Inst) i128 {
    if (inst.ty == .bool) return @intFromBool(inst.immediates.imm != 0);
    if (inst.ty == .u64) return inst.immediates.imm;
    return @as(i64, @bitCast(inst.immediates.imm));
}

fn clone(a: Allocator, function: form.Function) Allocator.Error!form.Function {
    var out = function;
    out.pre = try a.dupe(form.Inst, function.pre);
    const blocks = try a.alloc(form.Block, function.blocks.len);
    for (blocks, function.blocks) |*slot, block| {
        slot.* = block;
        slot.phis = try a.dupe(form.Phi, block.phis);
        slot.insts = try a.dupe(form.Inst, block.insts);
    }
    out.blocks = blocks;
    const sites = try a.alloc(form.Site, function.aux.sites.len);
    @memcpy(sites, function.aux.sites);
    out.aux.sites = sites;
    return out;
}

fn replace(a: Allocator, module: form.Module, index: usize, function: form.Function) Allocator.Error!form.Module {
    const functions = try a.dupe(form.Function, module.functions);
    functions[index] = function;
    return .{ .functions = functions };
}

fn removeAt(a: Allocator, comptime T: type, items: []const T, at: usize) Allocator.Error![]const T {
    const out = try a.alloc(T, items.len - 1);
    @memcpy(out[0..at], items[0..at]);
    @memcpy(out[at..], items[at + 1 ..]);
    return out;
}

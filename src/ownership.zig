//! The ownership analysis (`OWNERSHIP-ANALYSIS-1`): one runtime-independent
//! answer, per function, to what value semantics would cost it.
//!
//! It runs over the bytecode the native emitter lowers and reads the same
//! liveness solution the emitter plans its garbage-collection roots on
//! (`qbe_liveness.solve`), so a move it claims and a root the emitter drops rest
//! on one answer. For every transfer of a non-scalar value it says whether the
//! value moves, is borrowed or would need a real copy; for every in-place write
//! of a managed payload it says where a copy-on-write check would go and which
//! loop entry that check can be hoisted to. It never refuses: a fact it cannot
//! prove is answered conservatively (`owned`, `copy`, not hoisted).
//!
//! The analysis descends from the E2b reference-counting prototype
//! (`exp/e2b-rc-runtime:src/qbe_rc_*.zig`): its local classification and loop
//! hoisting are ported here without the counts, the refusals and the emission
//! the prototype needed for its runtime.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const liveness = @import("qbe_liveness.zig");
const model = @import("ownership_model.zig");
const sources = @import("ownership_sources.zig");
const roles = @import("ownership_roles.zig");
const cow = @import("ownership_cow.zig");
const transfer_class = @import("ownership_classify.zig");
const values = @import("ownership_values.zig");

/// What one transfer costs under value semantics.
pub const Class = model.Class;
/// Where a transferred value lands.
pub const Kind = model.Kind;
/// What a local's slot means for ownership.
pub const Role = model.Role;
/// One transfer of a non-scalar value.
pub const Transfer = model.Transfer;
/// One copy-on-write check site.
pub const Cow = model.Cow;
/// The finished analysis of one function.
pub const Analysis = model.Analysis;
/// Where an operand came from.
pub const Source = sources.Source;
/// The absent index or pc.
pub const none = model.none;
/// The failures the analysis can meet.
pub const Error = model.Error;

/// What the analysis reads: the function, its typed operand stacks, and the
/// liveness solution the emitter solved for it.
pub const Input = struct {
    program: bytecode.Program,
    function: bytecode.Function,
    states: []const ?[]const typed.Type,
    live: liveness.Solution,
};

/// Analyze one function. Every allocation comes from `a`, which should be an
/// arena: the result borrows from it and nothing is freed on its own.
pub fn analyze(a: std.mem.Allocator, input: Input) Error!Analysis {
    const code = input.function.scope.instructions;
    const count = input.function.scope.locals.len;
    var ctx: model.Context = .{
        .allocator = a,
        .code = .{ .program = input.program, .function = input.function, .states = input.states },
        .live = input.live,
        .flow = try sources.simulate(a, input.program, input.function, input.states),
        .locals = try localsFor(a, input),
        .defs = .{ .count = try zeroed(u32, a, count, 0), .pc = try zeroed(u32, a, count, none), .mutated = try zeroed(bool, a, count, false) },
        .marks = .{
            .unique_load = try zeroed(bool, a, code.len, false),
            .path_read = try zeroed(bool, a, code.len, false),
            .suppressed = try zeroed(bool, a, code.len, false),
            .plain_read = try zeroed(bool, a, code.len, false),
        },
    };
    try roles.classify(&ctx);
    const moves = try zeroed(bool, a, code.len, false);
    for (0..code.len) |pc| if (ctx.reachable(pc)) {
        moves[pc] = cow.movedAt(&ctx, pc) != null;
    };
    const transfers = try collectTransfers(&ctx);
    const cows = try cow.place(&ctx);
    const copies = try values.decide(&ctx);
    return .{ .roles = ctx.locals.roles, .parents = ctx.locals.parents, .transfers = transfers, .cows = cows, .moves = moves, .operands = ctx.flow.at, .copies = copies };
}

fn zeroed(comptime T: type, a: std.mem.Allocator, count: usize, value: T) Error![]T {
    const items = try a.alloc(T, count);
    @memset(items, value);
    return items;
}

fn localsFor(a: std.mem.Allocator, input: Input) Error!model.Locals {
    const list = input.function.scope.locals;
    const locals: model.Locals = .{
        .list = list,
        .params = input.function.signature.parameter_count,
        .value = try zeroed(bool, a, list.len, false),
        .managed = try zeroed(bool, a, list.len, false),
        .roles = try zeroed(Role, a, list.len, .plain),
        .parents = try zeroed(u32, a, list.len, none),
        .step = try zeroed(bool, a, list.len, false),
    };
    for (list, 0..) |local, i| {
        locals.value[i] = local.ty.isAggregate();
        locals.managed[i] = model.holdsManaged(input.program, local.ty, 0);
    }
    return locals;
}

/// Every transfer of the function, in program order.
fn collectTransfers(ctx: *model.Context) Error![]const Transfer {
    var found: std.ArrayList(Transfer) = .empty;
    for (ctx.instructions(), 0..) |instruction, pc| {
        const stack = ctx.flow.at[pc] orelse continue;
        const types = ctx.code.states[pc].?;
        const site: Site = .{ .ctx = ctx, .found = &found, .pc = pc, .stack = stack, .types = types };
        try transfersAt(site, instruction.op);
    }
    return found.toOwnedSlice(ctx.allocator);
}

/// One instruction whose transfers are being collected.
const Site = struct {
    ctx: *model.Context,
    found: *std.ArrayList(Transfer),
    pc: usize,
    stack: []const Source,
    types: []const typed.Type,

    /// Record the transfer of the operand `depth` places below the top.
    fn add(self: Site, depth: usize, kind: Kind, target: u32) Error!void {
        if (depth >= self.stack.len) return;
        const at = self.stack.len - 1 - depth;
        if (!self.types[at].isAggregate()) return;
        const source = self.stack[at];
        const class = transfer_class.classify(self.ctx, .{ .source = source, .kind = kind, .target = target, .ty = self.types[at] }, null);
        try self.found.append(self.ctx.allocator, .{ .pc = @intCast(self.pc), .kind = kind, .source = source, .target = target, .class = class });
    }
};

fn transfersAt(site: Site, op: model.Op) Error!void {
    const ctx = site.ctx;
    switch (op) {
        .store_local => |slot| {
            const target = model.li(slot);
            try site.add(0, if (ctx.locals.list[target].origin == .iteration) .binding else .assign, target);
        },
        .ret => try site.add(0, .@"return", none),
        .call => |callee| try arguments(site, ctx.code.program.functions[@backingInt(callee)]),
        .make_record => |record| {
            const kind: Kind = if (ctx.record(record.ty).isCollection()) .element else .construct;
            for (0..record.fields) |depth| try site.add(depth, kind, none);
        },
        .make_variant => |variant| if (ctx.record(variant.ty).shape.variants.?.cases[variant.tag].payload != null) try site.add(0, .construct, none),
        .update_record => |update| {
            for (0..update.indices.len) |depth| try site.add(depth, .field, none);
            try site.add(update.indices.len, .update, none);
        },
        .replace_index => try site.add(0, .element, none),
        .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |slot| try binding(site, model.li(slot)),
        .buffer_operation => |operation| try bufferTransfers(site, operation),
        else => {},
    }
}

/// A match arm's payload binding: a field of the scrutinee.
fn binding(site: Site, target: u32) Error!void {
    if (site.stack.len == 0 or !site.ctx.locals.value[target]) return;
    var source = site.stack[site.stack.len - 1];
    if (source.origin == .local) source.part = .field;
    const class = transfer_class.classify(site.ctx, .{ .source = source, .kind = .binding, .target = target, .ty = site.ctx.locals.list[target].ty }, null);
    try site.found.append(site.ctx.allocator, .{ .pc = @intCast(site.pc), .kind = .binding, .source = source, .target = target, .class = class });
}

fn arguments(site: Site, callee: bytecode.Function) Error!void {
    const count = callee.signature.parameter_count;
    for (0..count) |position| {
        // A `mut` argument is written in place, not transferred: its
        // copy-on-write site is placed by `ownership_cow.zig`.
        if (model.writesParameter(callee, position)) continue;
        try site.add(count - 1 - position, .argument, none);
    }
}

fn bufferTransfers(site: Site, operation: @FieldType(model.Op, "buffer_operation")) Error!void {
    const owner = model.li(operation.owner);
    const ty = site.ctx.locals.list[owner].ty;
    const dictionary = ty.isAggregate() and site.ctx.record(ty).collection.kind == .dictionary;
    switch (operation.kind) {
        .append, .set_add, .insert => try site.add(0, .element, none),
        .write => if (dictionary) {
            try site.add(0, .dict_value, none);
            try site.add(1, .element, none);
        } else try site.add(0, .element, none),
        .setdefault => try site.add(0, .dict_value, none),
        else => {},
    }
}

//! Which locals of a function are second names for another local's value
//! (`borrowed`), which are compiler temporaries written through to it
//! (`path`), and which hold a value of their own (`OWNERSHIP-ANALYSIS-1`).
//!
//! Ported from the E2b reference-counting prototype's classification
//! (`exp/e2b-rc-runtime:src/qbe_rc_classify.zig`), generalised so it never
//! refuses: where a borrow cannot be proved, the local is `owned` and the
//! transfer that fills it is a copy.
const std = @import("std");
const typed = @import("typed.zig");
const model = @import("ownership_model.zig");
const sources = @import("ownership_sources.zig");

const Context = model.Context;
const Error = model.Error;
const Op = model.Op;
const li = model.li;
const none = model.none;

/// Classify every local of the context's function.
pub fn classify(ctx: *Context) Error!void {
    try gather(ctx);
    spreadWrites(ctx);
    for (0..ctx.locals.list.len) |i| classifyOne(ctx, i);
    var rounds: usize = 0;
    while (true) : (rounds += 1) {
        if (rounds > ctx.locals.list.len + 4) return error.InternalError;
        markPathEffects(ctx);
        if (!demoteInvalid(ctx)) break;
    }
}

/// Count every local's stores and find the writes through each local.
fn gather(ctx: *Context) Error!void {
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (!ctx.reachable(pc)) continue;
        switch (instruction.op) {
            .store_local => |slot| {
                ctx.defs.count[li(slot)] += 1;
                ctx.defs.pc[li(slot)] = @intCast(pc);
            },
            .move_local => |slot| ctx.defs.mutated[li(slot)] = true,
            // A match binding is written on an edge, never counted as the one
            // store a borrow needs.
            .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |slot| {
                ctx.defs.count[li(slot)] += 2;
            },
            .buffer_operation => |operation| if (model.writesReceiver(operation.kind)) {
                ctx.defs.mutated[li(operation.owner)] = true;
            },
            .ref_local => |slot| ctx.defs.mutated[li(slot)] = true,
            else => {},
        }
    }
    try uniqueLoads(ctx);
    for (ctx.marks.unique_load, 0..) |loaded, pc| if (loaded) switch (ctx.instructions()[pc].op) {
        .load_local => |slot| ctx.defs.mutated[li(slot)] = true,
        else => {},
    };
}

/// The source a once-stored local was filled from.
const Origin = struct { local: u32, source: sources.Source, pc: usize };

fn singleSource(ctx: *const Context, i: usize) ?Origin {
    if (ctx.defs.count[i] != 1) return null;
    const d = ctx.defs.pc[i];
    if (d == none) return null;
    const stack = ctx.flow.at[d] orelse return null;
    if (stack.len == 0) return null;
    const source = stack[stack.len - 1];
    if (source.origin != .local) return null;
    return .{ .local = source.local, .source = source, .pc = d };
}

/// A temporary written through makes the local it was filled from written
/// through too: `c[i][j] = v` writes through `c[i]`'s place.
fn spreadWrites(ctx: *Context) void {
    var spreading = true;
    while (spreading) {
        spreading = false;
        for (0..ctx.locals.list.len) |i| {
            const from = singleSource(ctx, i) orelse continue;
            if (!ctx.defs.mutated[i] or !ctx.temporary(i)) continue;
            if (from.local == i or ctx.defs.mutated[from.local] or !ctx.locals.managed[from.local]) continue;
            ctx.defs.mutated[from.local] = true;
            spreading = true;
        }
    }
}

fn classifyOne(ctx: *Context, i: usize) void {
    const locals = &ctx.locals;
    if (!locals.value[i]) {
        locals.roles[i] = .plain;
        return;
    }
    if (i < locals.params) {
        const written = ctx.defs.count[i] != 0 or ctx.defs.mutated[i];
        locals.roles[i] = if (model.writesParameter(ctx.code.function, i)) .mut_param else if (written) .owned else .param;
        return;
    }
    locals.roles[i] = .owned;
    const origin = singleSource(ctx, i) orelse return;
    if (origin.local == i or !locals.value[origin.local]) return;
    // A source that dies at the store hands its value over: the local owns it
    // (a move). A parameter the caller owns never hands it over.
    const source_role = locals.roles[origin.local];
    const stable = origin.local < locals.params and (source_role == .param or source_role == .mut_param);
    const moved = origin.source.part == .whole and !ctx.live.after(origin.pc, origin.local);
    if (!stable and moved) return;
    if (ctx.defs.mutated[i]) {
        if (!ctx.temporary(i) or !locals.managed[i]) return;
        if (origin.source.part == .field) return;
        locals.roles[i] = .path;
    } else locals.roles[i] = .borrowed;
    locals.parents[i] = origin.local;
    locals.step[i] = origin.source.part != .whole;
}

/// Demote every borrow or path the function can break; answer whether any was.
fn demoteInvalid(ctx: *Context) bool {
    var changed = false;
    for (0..ctx.locals.list.len) |i| {
        const r = ctx.locals.roles[i];
        if (r != .borrowed and r != .path) continue;
        const local: u32 = @intCast(i);
        if (validBorrow(ctx, local, ctx.defs.pc[i])) continue;
        ctx.locals.roles[i] = .owned;
        ctx.locals.parents[i] = none;
        ctx.locals.step[i] = false;
        changed = true;
    }
    return changed;
}

/// Record which loads and reads the path locals turn into unique accesses: the
/// root load of a path whose parent is owned, and the element read that fills
/// a path local.
fn markPathEffects(ctx: *Context) void {
    @memset(ctx.marks.path_read, false);
    for (0..ctx.locals.list.len) |i| {
        if (ctx.locals.roles[i] != .path) continue;
        const d = ctx.defs.pc[i];
        const origin = singleSource(ctx, i) orelse continue;
        if (origin.source.part == .element) {
            markElementRead(ctx, d);
        } else if (origin.source.read != none) {
            if (ctx.role(ctx.locals.parents[i]) == .owned) ctx.marks.unique_load[origin.source.read] = true;
        }
    }
}

/// Mark the element read immediately feeding the store at `d`.
fn markElementRead(ctx: *Context, d: usize) void {
    var at = d;
    while (at > 0) {
        at -= 1;
        switch (ctx.instructions()[at].op) {
            .buffer_operation => {
                ctx.marks.path_read[at] = true;
                return;
            },
            .get_index => return,
            else => {},
        }
    }
}

/// Whether a borrow or path filled at `d` stays a second name for as long as
/// it is live: its root keeps the value (it is live, or a parameter the
/// caller keeps), and nothing writes the root's tree while it is.
fn validBorrow(ctx: *const Context, local: u32, d: u32) bool {
    const r = ctx.role(local);
    const parent = ctx.locals.parents[local];
    const parent_role = ctx.role(parent);
    if (r == .borrowed and ctx.defs.mutated[local]) return false;
    const path_parent = parent_role == .owned or parent_role == .path or parent_role == .mut_param;
    if (r == .path and !path_parent) return false;
    const root = ctx.rootOf(local);
    if (r == .path and !reference(ctx, ctx.locals.list[root].ty)) return false;
    if (ctx.alias(root)) return false;
    const root_role = ctx.role(root);
    const stable = root < ctx.locals.params and (root_role == .param or root_role == .mut_param);
    if (!stable and !ctx.live.after(d, root)) return false;
    const through: ?u32 = if (r == .path) local else null;
    for (ctx.instructions(), 0..) |_, pc| {
        if (!ctx.reachable(pc) or pc == d) continue;
        if (!ctx.live.before(pc, local)) continue;
        if (!stable and !ctx.live.before(pc, root)) return false;
        if (ctx.writesTree(pc, root, through)) return false;
    }
    return true;
}

/// Mark the loads that must first make their local unique: an argument to a
/// parameter the callee writes, and an operand of a write that is its own
/// receiver (`xs.sort(key=...)` passes `xs` as the sort's source).
fn uniqueLoads(ctx: *Context) Error!void {
    for (ctx.instructions(), 0..) |instruction, pc| {
        const stack = ctx.flow.at[pc] orelse continue;
        switch (instruction.op) {
            .buffer_operation => |operation| if (model.writesReceiver(operation.kind)) {
                const arity = operation.kind.arity();
                if (arity > stack.len) return error.InternalError;
                for (stack[stack.len - arity ..]) |operand| markReceiverLoad(ctx, operand, li(operation.owner));
            },
            .call => |target| {
                const callee = ctx.code.program.functions[@backingInt(target)];
                const count = callee.signature.parameter_count;
                if (count > stack.len) return error.InternalError;
                for (0..count) |position| {
                    if (!model.writesParameter(callee, position)) continue;
                    if (!ctx.managedType(callee.scope.locals[position].ty)) continue;
                    const operand = stack[stack.len - count + position];
                    if (operand.origin != .local or operand.part != .whole or operand.read == none) continue;
                    if (ctx.instructions()[operand.read].op != .load_local) continue;
                    ctx.marks.unique_load[operand.read] = true;
                }
            },
            else => {},
        }
    }
}

/// Whether a value of `ty` is one managed reference: a collection, a string or
/// a `class`, whose payload lives behind it.
fn reference(ctx: *const Context, ty: typed.Type) bool {
    return ty.isAggregate() and ctx.record(ty).managed;
}

fn markReceiverLoad(ctx: *Context, operand: sources.Source, owner: u32) void {
    if (operand.origin != .local or operand.part != .whole or operand.local != owner or operand.read == none) return;
    if (ctx.instructions()[operand.read].op != .load_local) return;
    ctx.marks.unique_load[operand.read] = true;
}

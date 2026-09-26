//! Which value-semantics copies must really copy (`VALUE-SEMANTICS-2`).
//!
//! Under value semantics lowering puts a `value_copy` after every value that
//! moves to a second home and is not fresh. This step answers, for each, the
//! question the ownership analysis already answers for every transfer: is it a
//! move (the source is never read again), a borrow (neither side is written
//! while both are read) or a copy. Only a copy emits anything.
//!
//! Three corrections keep the analysis sound for values rather than for the
//! reference runtime it was written against:
//! - A local whose value may be shared is not its own value, so reading it for
//!   the last time is no move: a parameter holds the caller's lent value, a
//!   local filled from a place without a copy site holds that place (lowering
//!   never copies into a compiler temporary, which is a path, nor into a
//!   spliced callee's parameter), and a local some copy site filled with a
//!   borrow holds that borrow. The last set grows with the borrows this step
//!   finds, so it is solved to a fixed point. A local filled without a copy
//!   site is not even a safe root to borrow from: its source is untracked.
//! - A value read through a `class` object, Cell or live view is shared storage the
//!   analysis cannot follow (any other name of the object may write it), so it
//!   is always copied.
//! - A read-only argument that a `mut` argument of the same call could reach
//!   (`argument`) and the elements of a fresh shallow copy (`children`) are
//!   always copied; lowering proved the first and the second is never a move.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const model = @import("ownership_model.zig");
const sources = @import("ownership_sources.zig");
const transfer_class = @import("ownership_classify.zig");

const Context = model.Context;
const Error = model.Error;
const none = model.none;
const li = model.li;

/// Per instruction, whether its `value_copy` must copy; empty when the
/// function has no `value_copy` at all (always, with the switch off).
pub fn decide(ctx: *const Context) Error![]const bool {
    const code = ctx.instructions();
    var any = false;
    for (code) |instruction| if (instruction.op == .value_copy) {
        any = true;
    };
    if (!any) return &.{};
    const a = ctx.allocator;
    const copies = try a.alloc(bool, code.len);
    @memset(copies, false);
    const arms = try armSwitches(ctx);
    const raw = try rawAliases(ctx, arms);
    const owners = try ctx.allocator.alloc(bool, raw.len);
    for (owners, raw, 0..) |*owner, alias, index| owner.* = index >= ctx.locals.params and ctx.role(@intCast(index)) == .owned and !alias;
    const step: Step = .{ .ctx = ctx, .owners = owners, .raw = raw, .arms = arms };
    // Each round can only take locals out of `owners`, so it settles.
    var rounds: usize = 0;
    while (rounds <= ctx.locals.list.len + 1) : (rounds += 1) {
        if (!step.round(copies)) break;
    }
    @import("ownership_field_return.zig").elide(ctx, owners, copies);
    @import("ownership_index_return.zig").elide(ctx, copies);
    return copies;
}

/// Per local, whether some store fills it from a place with no copy site in
/// between, so it may hold that place itself: a compiler temporary, a spliced
/// callee's parameter, or a match binding whose arm keeps the payload as it is.
fn rawAliases(ctx: *const Context, arms: []const u32) Error![]bool {
    const code = ctx.instructions();
    const raw = try ctx.allocator.alloc(bool, ctx.locals.list.len);
    @memset(raw, false);
    for (code, 0..) |instruction, pc| {
        if (!ctx.reachable(pc)) continue;
        const stack = ctx.flow.at[pc] orelse continue;
        const fresh = stack.len != 0 and stack[stack.len - 1].origin == .fresh;
        switch (instruction.op) {
            .store_local => |slot| {
                const copied = pc > 0 and code[pc - 1].op == .value_copy;
                if (!copied and !fresh) raw[li(slot)] = true;
            },
            .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |slot| {
                if (!fresh and !payloadCopied(code, arms, arm.target)) raw[li(slot)] = true;
            },
            else => {},
        }
    }
    return raw;
}

/// Whether the arm starting at `target` rebinds its payload through a copy
/// site (`load_local`, `value_copy`, `store_local` at its head).
fn payloadCopied(code: []const bytecode.Instruction, arms: []const u32, target: usize) bool {
    if (target + 1 >= code.len or arms[target] == none) return false;
    return switch (code[target + 1].op) {
        .value_copy => |copy| copy.site == .payload,
        else => false,
    };
}

/// Per instruction, the `switch_variant` whose arm starts there, or `none`.
fn armSwitches(ctx: *const Context) Error![]u32 {
    const code = ctx.instructions();
    const arms = try ctx.allocator.alloc(u32, code.len);
    @memset(arms, none);
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.target < arms.len) arms[arm.target] = @intCast(pc);
        },
        else => {},
    };
    return arms;
}

/// The facts one classification round reads.
const Step = struct {
    ctx: *const Context,
    owners: []bool,
    raw: []const bool,
    arms: []const u32,

    /// Classify every copy site once; answer whether a local left `owners`.
    fn round(self: Step, copies: []bool) bool {
        var changed = false;
        for (self.ctx.instructions(), 0..) |instruction, pc| {
            const copy = switch (instruction.op) {
                .value_copy => |copy| copy,
                else => continue,
            };
            if (!self.ctx.reachable(pc)) continue;
            const site = self.siteAt(pc, copy) orelse {
                copies[pc] = true;
                continue;
            };
            const class = self.classify(site);
            copies[pc] = class == .copy;
            // A local filled with a borrow shares its value from then on.
            if (class == .borrow and site.question.target != none and self.owners[site.question.target]) {
                self.owners[site.question.target] = false;
                changed = true;
            }
        }
        return changed;
    }

    /// The transfer a copy site stands for, or null when it always copies.
    fn siteAt(self: Step, pc: usize, copy: bytecode.ValueCopy) ?Site {
        const ctx = self.ctx;
        const code = ctx.instructions();
        switch (copy.site) {
            .argument, .children => return null,
            .payload => {
                // The arm reloads its binding (`pc - 1`) and stores the copy
                // back; the value is the scrutinee's payload at the switch.
                if (pc == 0 or self.arms[pc - 1] == none) return null;
                const at = self.arms[pc - 1];
                const stack = ctx.flow.at[at] orelse return null;
                if (stack.len == 0) return null;
                var source = stack[stack.len - 1];
                if (source.origin == .local) source.part = .field;
                const target = switch (code[pc - 1].op) {
                    .load_local => |slot| li(slot),
                    else => return null,
                };
                return .{ .question = .{ .source = source, .kind = .binding, .target = target, .ty = copy.ty } };
            },
            .assign, .store, .ret => {
                const stack = ctx.flow.at[pc] orelse return null;
                if (stack.len == 0) return null;
                const source = stack[stack.len - 1];
                var target: u32 = none;
                var kind: model.Kind = if (copy.site == .ret) .@"return" else .construct;
                if (copy.site == .assign and pc + 1 < code.len) switch (code[pc + 1].op) {
                    .store_local => |slot| {
                        target = li(slot);
                        kind = if (ctx.locals.list[target].origin == .iteration) .binding else .assign;
                    },
                    else => {},
                };
                return .{ .question = .{ .source = source, .kind = kind, .target = target, .ty = copy.ty } };
            },
        }
    }

    /// Move, borrow or copy for one site, with the value-semantics
    /// corrections this module's header describes.
    fn classify(self: Step, at: Site) model.Class {
        const source = at.question.source;
        switch (source.origin) {
            // Lowering saw a place the analysis calls fresh (a value a
            // collection keeps, such as `setdefault`'s): copy.
            .fresh, .unknown => return .copy,
            .local => {},
        }
        if (transfer_class.sharedProjection(self.ctx, source, self.raw)) return .copy;
        return transfer_class.classify(self.ctx, at.question, self.owners);
    }
};

/// One copy site as the transfer it stands for.
const Site = struct { question: transfer_class.Question };

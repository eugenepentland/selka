//! Move, borrow or copy for one transfer of a non-scalar value
//! (`OWNERSHIP-ANALYSIS-1`). The ownership analysis (`ownership.zig`)
//! classifies every transfer it collects with it, and the value-semantics copy
//! placement (`ownership_values.zig`) classifies its copy sites with it too, so
//! the two cannot disagree on what a move or a borrow is.
const typed = @import("typed.zig");
const model = @import("ownership_model.zig");
const sources = @import("ownership_sources.zig");

const Class = model.Class;
const Kind = model.Kind;
const none = model.none;

/// One transfer being classified: where its value comes from, where it lands
/// (`target` names the local of an `assign` or `binding`), and its type.
pub const Question = struct { source: sources.Source, kind: Kind, target: u32, ty: typed.Type };

/// Move, borrow or copy (see `Class`). `owners`, when given, names the locals
/// whose value is their own; a local outside it never hands its value over,
/// because the value it holds may be shared with another name
/// (`VALUE-SEMANTICS-2`). Without it every `owned` local may.
pub fn classify(ctx: *const model.Context, question: Question, owners: ?[]const bool) Class {
    const source = question.source;
    switch (source.origin) {
        .fresh => return .move,
        .unknown => return .copy,
        .local => {},
    }
    if (independentHome(ctx, question) and sharedProjection(ctx, source, null)) return .copy;
    const local = source.local;
    const moved = movable(ctx, local, owners) and source.read != none and !ctx.live.after(source.read, local);
    if (question.kind == .argument) return if (moved and source.part == .whole) .move else .borrow;
    if (moved) return .move;
    if (immutable(ctx, question.ty)) return .borrow;
    switch (question.kind) {
        .assign, .binding => if (question.target != none) {
            if (ctx.alias(question.target) and ctx.locals.parents[question.target] == local) return .borrow;
            if (readOnlyShare(ctx, question.target, local)) return .borrow;
        },
        else => {},
    }
    return .copy;
}

// Compiler receiver temporaries are loans, not semantic publications. Their
// existing lifetime/callback planning decides whether a capture needs sharing;
// forcing all view projections to copy would snapshot list(view)'s receiver.
fn independentHome(ctx: *const model.Context, question: Question) bool {
    if (question.kind == .argument) return false;
    if (question.kind != .assign or question.target == none) return true;
    return !ctx.temporary(question.target);
}

/// Whether a local or match binding may share its source's payload: it is
/// never written through, and wherever it is live the source's root keeps its
/// value (it is live, or a parameter the caller keeps) and nothing writes the
/// root's tree.
fn readOnlyShare(ctx: *const model.Context, target: u32, local: u32) bool {
    if (ctx.defs.mutated[target]) return false;
    const root = ctx.rootOf(local);
    const root_role = ctx.role(root);
    const stable = root < ctx.locals.params and (root_role == .param or root_role == .mut_param);
    for (0..ctx.instructions().len) |pc| {
        if (!ctx.reachable(pc) or !ctx.live.before(pc, target)) continue;
        if (!stable and !ctx.live.before(pc, root)) return false;
        if (ctx.writesTree(pc, root, null)) return false;
    }
    return true;
}

/// Whether reading `local` for the last time can hand its value over: it holds
/// a value of its own, not one the caller or another local keeps.
fn movable(ctx: *const model.Context, local: u32, owners: ?[]const bool) bool {
    if (ctx.role(local) != .owned) return false;
    const table = owners orelse return true;
    return local < table.len and table[local];
}

/// Whether no value of `ty` can be written in place, so sharing one is free: a
/// string, an immutable byte string, or a scalar-only value record.
fn immutable(ctx: *const model.Context, ty: typed.Type) bool {
    if (!ty.isAggregate()) return true;
    const schema = ctx.record(ty);
    // A `byte_buffer` shares the byte collection kind with `bytes` but is
    // written in place, so only `str` and `bytes` are immutable.
    if (schema.managed) return schema.collection.kind == .string or typed.isByteString(schema);
    return !ctx.managedType(ty);
}

/// Whether a projection crosses externally held identity, or an untracked
/// raw alias when that table is supplied. A last read cannot move a live view
/// mapping; alias steps preserve this boundary through materialized paths.
pub fn sharedProjection(ctx: *const model.Context, source: sources.Source, raw: ?[]const bool) bool {
    if (source.origin != .local) return false;
    var at = source.local;
    var part = source.part != .whole;
    var guard: usize = 0;
    while (guard <= ctx.locals.list.len) : (guard += 1) {
        if (at >= ctx.locals.list.len) return true;
        const values = @import("value_semantics.zig");
        const ty = ctx.locals.list[at].ty;
        if (part and (values.sharedFields(ctx.code.program.records, ty) or values.containsLiveView(ctx.code.program.records, ty))) return true;
        if (raw) |table| if (table[at] and !ctx.alias(at)) return true;
        if (!ctx.alias(at)) return false;
        part = part or ctx.locals.step[at];
        at = ctx.locals.parents[at];
        if (at == none) return false;
    }
    return true;
}

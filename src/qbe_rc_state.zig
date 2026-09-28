//! Function-arena RC state over finalized ownership and physical storage.
const std = @import("std");
const typed = @import("typed.zig");
const model = @import("rc_model.zig");
const shape = @import("rc_shape.zig");
const plan = @import("rc_plan.zig");
const calls = @import("rc_calls.zig");
const runtime = @import("runtime_mode.zig");
const journal = @import("qbe_rc_journal.zig");
const readonly_anchor = @import("qbe_rc_readonly_anchor.zig");

/// A stack position's stable owned-value storage; its type can change at joins.
pub const Operand = journal.Operand;
/// Independent record emission certificates; none changes journal storage.
pub const Records = struct {
    transfers: []const @import("rc_field_transfer.zig").Certificate = &.{},
    writes: []const @import("rc_plain_record_write.zig").Certificate = &.{},
    reads: []@import("rc_record_read.zig").Certificate = &.{},
    /// RC-INTERVAL-ANCHOR-2: per local, the list root it is bound to (the
    /// root's own index for an accepted root), or `cow_plan.none`.
    intervals: []const u32 = &.{},
    /// Match arms that move their element's payload (RC-ELEMENT-TAKE-1).
    takes: []const @import("rc_element_take.zig").Take = &.{},
};
/// Semantic obligations paired with independent emission-only journal indices.
pub const EmissionPlan = struct {
    locals: plan.Plan,
    journal: journal.Layout,
    records: Records = .{},
    dictionary_tails: []const @import("rc_dictionary_tail.zig").Certificate = &.{},
    append_loops: []const @import("rc_append_loop.zig").Certificate = &.{},
    readonly: ?@import("rc_readonly_calls.zig").Certificate = null,
    /// Fills of the receiver place scopes whose records this frame owns.
    scope_records: []const usize = &.{},
};
/// Final immutable plan and reusable lowering scratch, owned by the function arena.
pub const State = struct {
    catalog: shape.Catalog,
    plan: EmissionPlan,
    contract: model.CallContract,
    operands: []Operand,
    pending: u64,
    active: bool,
    readonly: bool = false,
};
/// Internal compiler failures; legal programs never decline RC lowering.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Build after COW's hidden receiver/key reads have reached their liveness fixpoint.
pub fn build(comptime E: type, self: *E, capacity: usize) Error!*State {
    const a = self.allocator;
    const state = try a.create(State);
    state.catalog = shape.Catalog.init(a, self.layouts) catch |err| return translate(err);
    state.contract = calls.guest(a, &state.catalog, self.function, runtime.identity()) catch |err| return translate(err);
    const locals = try a.alloc(@import("rc_input.zig").Binding, self.function.scope.locals.len);
    for (locals, 0..) |*binding, index| binding.* = .{ .storage = @fromBackingInt(@intCast(index)) };
    try @import("qbe_rc_read_loans.zig").bind(E, self, locals, &state.catalog);
    try readonly_anchor.bind(E, self, locals, &state.catalog, state.contract);
    try readonly_anchor.bindIntervals(E, self, locals, &state.catalog, state.contract);
    const intervals = try readonly_anchor.bindLists(E, self, locals, &state.catalog, state.contract);
    try settleElements(E, self, locals);
    state.plan.locals = plan.build(a, .{
        .code = .{ .program = self.program, .function = self.function, .states = self.states },
        .flow = .{ .live = self.live.?, .ownership = self.ownership.? },
        .physical = .{ .catalog = &state.catalog, .locals = locals },
        .mutation = .{ .places = self.cow.?.plan },
        .contracts = .{ .current = state.contract },
        .policy = .{ .abi = runtime.identity() },
    }) catch |err| return translate(err);
    state.active = false;
    state.readonly = false;
    for (state.plan.locals.storage) |slot| state.active = state.active or slot.shape.counted or slot.shape.unique_drop;
    state.operands = try a.alloc(Operand, capacity);
    @memset(state.operands, .{});
    state.pending = @max(8, (try self.layout(self.function.signature.return_type)).size);
    for (self.states) |maybe| if (maybe) |stack| for (stack, 0..) |ty, index| {
        const owned = try owns(state, ty);
        state.active = state.active or owned;
        state.operands[index].may_own = state.operands[index].may_own or owned;
        const bytes = (try self.layout(ty)).size;
        state.operands[index].bytes = @max(state.operands[index].bytes, bytes);
        state.pending = @max(state.pending, bytes);
    };
    state.plan.dictionary_tails = &.{};
    state.plan.append_loops = &.{};
    state.plan.readonly = null;
    state.plan.records = .{ .intervals = intervals };
    state.plan.scope_records = &.{};
    state.plan.journal = try journal.build(a, state.plan.locals.storage, state.operands);
    state.plan.records.transfers = try @import("rc_field_transfer.zig").build(E, self, &state.catalog);
    state.plan.records.takes = try @import("rc_element_take.zig").build(E, self, &state.catalog);
    state.plan.records.writes = try @import("rc_plain_record_write.zig").build(E, self, &state.catalog, state.plan.locals);
    return state;
}

/// RC-ELEMENT-BORROW-3: an owning element borrow stands only where its slot
/// is bound as borrowed from a parameter's storage. Any other is withdrawn
/// here, before the plan reads the bindings, so it keeps an ordinary owner.
fn settleElements(comptime E: type, self: *E, locals: []const @import("rc_input.zig").Binding) Error!void {
    for (self.function.scope.locals, locals, 0..) |local, binding, index| {
        if (!self.borrowsElement(index)) continue;
        const value = self.layout(local.ty) catch |err| return translate(err);
        if (!value.trace and !value.drop) continue;
        if (binding.anchor) |anchor| if (anchor == .storage and @backingInt(anchor.storage) < self.function.signature.parameter_count) continue;
        @constCast(self.by_reference)[index] = .none;
    }
}

/// A physical value can require cleanup even when semantic COW sees no leaves.
pub fn owns(state: *State, ty: typed.Type) Error!bool {
    const value = state.catalog.get(ty) catch |err| return translate(err);
    return value.counted or value.unique_drop;
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

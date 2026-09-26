//! Function-arena RC state over finalized ownership and physical storage.
const std = @import("std");
const typed = @import("typed.zig");
const model = @import("rc_model.zig");
const shape = @import("rc_shape.zig");
const plan = @import("rc_plan.zig");
const calls = @import("rc_calls.zig");
const runtime = @import("runtime_mode.zig");

/// A stack position's stable owned-value storage; its type can change at joins.
pub const Operand = struct { bytes: u64 = 8 };
/// Final immutable plan and reusable lowering scratch, owned by the function arena.
pub const State = struct {
    catalog: shape.Catalog,
    locals: plan.Plan,
    contract: model.CallContract,
    operands: []Operand,
    pending: u64,
    active: bool,
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
    state.locals = plan.build(a, .{
        .code = .{ .program = self.program, .function = self.function, .states = self.states },
        .flow = .{ .live = self.live.?, .ownership = self.ownership.? },
        .physical = .{ .catalog = &state.catalog, .locals = locals },
        .mutation = .{ .places = self.cow.?.plan },
        .contracts = .{ .current = state.contract },
        .policy = .{ .abi = runtime.identity() },
    }) catch |err| return translate(err);
    state.active = false;
    for (state.locals.storage) |slot| state.active = state.active or slot.shape.counted or slot.shape.unique_drop;
    state.operands = try a.alloc(Operand, capacity);
    @memset(state.operands, .{});
    state.pending = @max(8, (try self.layout(self.function.signature.return_type)).size);
    for (self.states) |maybe| if (maybe) |stack| for (stack, 0..) |ty, index| {
        state.active = state.active or try owns(state, ty);
        const bytes = (try self.layout(ty)).size;
        state.operands[index].bytes = @max(state.operands[index].bytes, bytes);
        state.pending = @max(state.pending, bytes);
    };
    return state;
}

/// A physical value can require cleanup even when semantic COW sees no leaves.
pub fn owns(state: *State, ty: typed.Type) Error!bool {
    const value = state.catalog.get(ty) catch |err| return translate(err);
    return value.counted or value.unique_drop;
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

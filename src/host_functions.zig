//! Trusted synchronous host registrations copy ordinary values across a checked boundary.
const std = @import("std");
const typed = @import("typed.zig");
const copy = @import("value_copy.zig");
const data_type = @import("data_type.zig");
const effects = @import("effect_set.zig");
/// Registry-local identity, resolved from an exact qualified declaration name.
pub const Id = enum(usize) { _ };
/// Reference passing remains explicit even while the first boundary rejects it.
pub const Parameter = struct { ty: typed.Type, passing: enum { value, shared, exclusive } = .value };
/// Exact nominal types and declared language-visible effects of a host operation.
pub const Signature = struct { parameters: []const Parameter, result: Parameter, effects: effects.Mask = 0 };
/// A compiler-resolved declaration; registration copies its name and parameter descriptors.
pub const Declaration = struct { name: []const u8, signature: Signature };
/// Callback failures are distinct from recoverable errors represented by returned guest results.
pub const CallbackError = copy.Error || error{ HostFailure, HostWorkLimit, HostSessionClosed, HostReentrant, HostReplayMismatch };
/// Registration, session, authority, and boundary-validation failures.
pub const Error = CallbackError || data_type.CheckError || error{
    HostUnknownFunction,
    HostDuplicateFunction,
    HostDuplicateRegistration,
    HostSignatureMismatch,
    HostBorrowUnsupported,
    HostInvalidEffects,
    HostMissingRegistration,
    HostCapabilityDenied,
    HostInvalidBudget,
    HostCallLimit,
    HostArity,
    HostGenerationExhausted,
};
/// Handwritten trusted wrapper; returned values are owned in Call.allocator().
pub const Binding = struct { signature: Signature, context: ?*anyopaque = null, invoke: *const fn (*Call) CallbackError!typed.Value };
/// Per-execution call/work limits and a shared input/output value-copy limit per call.
pub const Limits = struct { max_calls: u64 = 10000, max_work: u64 = 1000000, values: copy.Limits = .{} };
/// Copied arguments up to this arity stay in the caller's frame; longer ones spill to the allocator.
const inline_arguments = 8;
const Registered = struct { binding: Binding, grants: effects.Mask };
const Entry = struct { declaration: Declaration, registered: ?Registered = null };
const State = struct {
    epoch: u64 = 0,
    phase: enum { idle, running, callback } = .idle,
    allocator: ?std.mem.Allocator = null,
    limits: Limits = .{},
    calls: u64 = 0,
    work_remaining: u64 = 0,
    work_exhausted: bool = false,
};
/// Owns declarations and bindings; borrows an immutable nominal type catalog and callback contexts.
pub const Registry = struct {
    arena: std.heap.ArenaAllocator,
    records: []const typed.Record,
    entries: []Entry,
    state: State = .{},
    /// Validate and snapshot all declarations before installing any callbacks.
    pub fn init(allocator: std.mem.Allocator, records: []const typed.Record, declarations: []const Declaration) Error!Registry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const owned = arena.allocator();
        const entries = try owned.alloc(Entry, declarations.len);
        for (declarations, 0..) |declaration, index| {
            if (declaration.name.len == 0) return error.HostUnknownFunction;
            for (entries[0..index]) |previous| if (std.mem.eql(u8, previous.declaration.name, declaration.name)) return error.HostDuplicateFunction;
            try validateSignature(owned, records, declaration.signature);
            entries[index] = .{ .declaration = .{ .name = try owned.dupe(u8, declaration.name), .signature = declaration.signature } };
            entries[index].declaration.signature.parameters = try owned.dupe(Parameter, declaration.signature.parameters);
        }
        return .{ .arena = arena, .records = records, .entries = entries };
    }
    /// Release registry metadata after closing its session; returned call values remain caller-owned.
    pub fn deinit(self: *Registry) void {
        std.debug.assert(self.state.phase == .idle);
        self.arena.deinit();
    }
    /// Resolve a declaration without loading symbols or invoking host code.
    pub fn resolve(self: *const Registry, name: []const u8) Error!Id {
        for (self.entries, 0..) |entry, index| if (std.mem.eql(u8, entry.declaration.name, name)) return @fromBackingInt(index);
        return error.HostUnknownFunction;
    }
    /// Bind an exact signature and explicit effect grants; active sessions cannot change bindings.
    pub fn register(self: *Registry, name: []const u8, binding: Binding, grants: effects.Mask) Error!void {
        if (self.state.phase != .idle) return error.HostReentrant;
        const id = try self.resolve(name);
        const entry = &self.entries[@backingInt(id)];
        if (entry.registered != null) return error.HostDuplicateRegistration;
        if (!sameSignature(entry.declaration.signature, binding.signature)) return error.HostSignatureMismatch;
        if (grants & ~effects.all != 0) return error.HostInvalidEffects;
        if (binding.signature.effects & ~grants != 0) return error.HostCapabilityDenied;
        var installed = binding;
        installed.signature = entry.declaration.signature;
        entry.registered = .{ .binding = installed, .grants = grants };
    }
    /// Preflight every declaration and start one execution with fresh budgets and a stale-session guard.
    pub fn begin(self: *Registry, allocator: std.mem.Allocator, limits: Limits) Error!Session {
        if (self.state.phase != .idle) return error.HostReentrant;
        if (limits.max_calls == 0 or limits.max_work == 0) return error.HostInvalidBudget;
        if (limits.values.max_values == 0 or limits.values.max_depth == 0 or limits.values.max_depth > 128) return error.HostInvalidBudget;
        for (self.entries) |entry| {
            const installed = entry.registered orelse return error.HostMissingRegistration;
            if (entry.declaration.signature.effects & ~installed.grants != 0) return error.HostCapabilityDenied;
        }
        if (self.state.epoch == std.math.maxInt(u64)) return error.HostGenerationExhausted;
        self.state = .{ .epoch = self.state.epoch + 1, .phase = .running, .allocator = allocator, .limits = limits, .work_remaining = limits.max_work };
        return .{ .registry = self, .epoch = self.state.epoch };
    }
};
/// One caller-serialized execution; closing it does not invalidate independently copied results.
pub const Session = struct {
    registry: *Registry,
    epoch: u64,
    fn ready(self: Session) CallbackError!void {
        if (self.registry.state.epoch != self.epoch or self.registry.state.phase == .idle) return error.HostSessionClosed;
        if (self.registry.state.phase == .callback) return error.HostReentrant;
    }
    /// Close the execution, rejecting stale or callback-time attempts to alter its lifetime.
    pub fn close(self: Session) Error!void {
        try self.ready();
        self.registry.state.phase = .idle;
        self.registry.state.allocator = null;
    }
    /// Validate/copy arguments, invoke synchronously and copy the owned result back to the caller.
    pub fn call(self: Session, id: Id, arguments: []const typed.Value) Error!typed.Value {
        try self.ready();
        if (@backingInt(id) >= self.registry.entries.len) return error.HostUnknownFunction;
        const entry = self.registry.entries[@backingInt(id)];
        const installed = entry.registered orelse return error.HostMissingRegistration;
        const signature = entry.declaration.signature;
        if (arguments.len != signature.parameters.len) return error.HostArity;
        const state = &self.registry.state;
        if (state.calls == state.limits.max_calls) return error.HostCallLimit;
        if (state.work_remaining == 0) return error.HostWorkLimit;
        const allocator = state.allocator.?;
        // Small arities cover every declaration this boundary sees in practice;
        // keeping their copied arguments on the stack leaves a scalar host call
        // with no allocator round trip of its own.
        var reserved: [inline_arguments]typed.Value = undefined;
        const spilled = arguments.len > inline_arguments;
        const inputs = if (spilled) try allocator.alloc(typed.Value, arguments.len) else reserved[0..arguments.len];
        var initialized: usize = 0;
        defer {
            for (inputs[0..initialized]) |value| value.release(allocator);
            if (spilled) allocator.free(inputs);
        }
        var copier: copy.Copier = .{ .records = self.registry.records, .limits = state.limits.values };
        for (arguments, signature.parameters, inputs) |argument, parameter, *input| {
            input.* = try copier.copy(allocator, parameter.ty, argument);
            initialized += 1;
        }
        state.calls += 1;
        state.work_remaining -= 1;
        state.phase = .callback;
        defer state.phase = .running;
        var request: Call = .{
            .session = self,
            .arguments = inputs,
            .records = self.registry.records,
            .context = installed.binding.context,
            .result_type = signature.result.ty,
        };
        const result = try installed.binding.invoke(&request);
        defer result.release(allocator);
        if (state.work_exhausted) return error.HostWorkLimit;
        return copier.copy(allocator, signature.result.ty, result);
    }
};
/// Call-scoped borrowed inputs and trusted context; never retain these references after returning.
pub const Call = struct {
    session: Session,
    arguments: []const typed.Value,
    records: []const typed.Record,
    context: ?*anyopaque,
    result_type: typed.Type,
    /// Borrow the execution allocator for owned callback results; the call owns no allocator.
    pub fn allocator(self: *const Call) std.mem.Allocator {
        std.debug.assert(self.session.registry.state.phase == .callback);
        return self.session.registry.state.allocator.?;
    }
    /// Inspect cooperative work remaining for a recording adapter.
    pub fn remainingWork(self: *const Call) u64 {
        return self.session.registry.state.work_remaining;
    }
    /// Charge bounded native work cooperatively; the VM cannot preempt arbitrary callback code.
    pub fn consume(self: *Call, units: u64) CallbackError!void {
        const state = &self.session.registry.state;
        if (state.epoch != self.session.epoch or state.phase != .callback) return error.HostSessionClosed;
        if (units > state.work_remaining) {
            state.work_remaining = 0;
            state.work_exhausted = true;
            return error.HostWorkLimit;
        }
        state.work_remaining -= units;
    }
};
fn validateSignature(allocator: std.mem.Allocator, records: []const typed.Record, signature: Signature) Error!void {
    if (signature.effects & ~effects.all != 0) return error.HostInvalidEffects;
    if (signature.result.passing != .value) return error.HostBorrowUnsupported;
    try data_type.check(allocator, records, signature.result.ty, true);
    for (signature.parameters) |parameter| {
        if (parameter.passing != .value) return error.HostBorrowUnsupported;
        try data_type.check(allocator, records, parameter.ty, true);
    }
}
fn sameSignature(left: Signature, right: Signature) bool {
    if (left.result.ty != right.result.ty or left.result.passing != right.result.passing or left.effects != right.effects or left.parameters.len != right.parameters.len) return false;
    for (left.parameters, right.parameters) |a, b| if (a.ty != b.ty or a.passing != b.passing) return false;
    return true;
}

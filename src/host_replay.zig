//! Bounded in-memory host transcripts pinned to one checked record schema.
const std = @import("std");
const host = @import("host_functions.zig");
const typed = @import("typed.zig");
const copy = @import("value_copy.zig");
const Hash = std.crypto.hash.sha2.Sha256;
const Outcome = union(enum) { value: typed.Value, failure: host.CallbackError };
const Event = struct { identity: [32]u8, outcome: Outcome, work: u64 };
const Binding = struct { tape: *Transcript, name: []const u8, delegate: host.Binding };
/// Owns recorded copies and wrapper contexts; outlives wrapped registrations.
pub const Transcript = struct {
    allocator: std.mem.Allocator,
    limit: usize = 10000,
    storage: struct { events: std.ArrayList(Event) = .empty, bindings: std.ArrayList(*Binding) = .empty } = .{},
    state: struct { replaying: bool = false, cursor: usize = 0, failed: bool = false } = .{},
    records: ?[]const typed.Record = null,
    /// Release transcript-owned values and adapter contexts after registrations close.
    pub fn deinit(self: *Transcript) void {
        for (self.storage.events.items) |event| if (event.outcome == .value) event.outcome.value.release(self.allocator);
        for (self.storage.bindings.items) |binding| {
            self.allocator.free(binding.name);
            self.allocator.destroy(binding);
        }
        self.storage.events.deinit(self.allocator);
        self.storage.bindings.deinit(self.allocator);
    }
    /// Wrap a provider before ordinary registration; its signature/grants are unchanged.
    pub fn wrap(self: *Transcript, name: []const u8, delegate: host.Binding) std.mem.Allocator.Error!host.Binding {
        const binding = try self.allocator.create(Binding);
        errdefer self.allocator.destroy(binding);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        binding.* = .{ .tape = self, .name = owned_name, .delegate = delegate };
        try self.storage.bindings.append(self.allocator, binding);
        return .{ .signature = delegate.signature, .context = binding, .invoke = invoke };
    }
    /// Start a fresh replay only after the recording execution/session ended.
    pub fn replay(self: *Transcript) error{IncompleteTranscript}!void {
        if (self.state.failed) return error.IncompleteTranscript;
        self.state.replaying = true;
        self.state.cursor = 0;
    }
    /// Reject replay with missing, extra or changed host-call sequences.
    pub fn finish(self: *Transcript) error{IncompleteTranscript}!void {
        if (self.state.failed) return error.IncompleteTranscript;
        if (self.state.replaying and self.state.cursor != self.storage.events.items.len) return error.IncompleteTranscript;
    }
    fn perform(self: *Transcript, binding: *Binding, call: *host.Call) host.CallbackError!typed.Value {
        if (self.state.failed) return error.HostReplayMismatch;
        if (self.records) |records| {
            if (records.ptr != call.records.ptr or records.len != call.records.len) return error.HostReplayMismatch;
        } else self.records = call.records;
        var hash = Hash.init(.{});
        hash.update(binding.name);
        var visited: usize = 0;
        for (call.arguments) |value| try fingerprint(&hash, value, 0, &visited);
        const identity = hash.finalResult();
        if (self.state.replaying) {
            if (self.state.cursor == self.storage.events.items.len) return error.HostReplayMismatch;
            const event = self.storage.events.items[self.state.cursor];
            if (!std.mem.eql(u8, &identity, &event.identity)) return error.HostReplayMismatch;
            self.state.cursor += 1;
            call.consume(event.work) catch |failure| {
                self.state.failed = true;
                return failure;
            };
            return switch (event.outcome) {
                .failure => |failure| failure,
                .value => |value| duplicate(call.allocator(), call, value),
            };
        }
        if (self.storage.events.items.len == self.limit) return error.HostWorkLimit;
        try self.storage.events.ensureUnusedCapacity(self.allocator, 1);
        const before = call.remainingWork();
        var delegated = call.*;
        delegated.context = binding.delegate.context;
        const result = binding.delegate.invoke(&delegated) catch |failure| {
            // Host allocator failure cannot yield a reliable replay certificate.
            if (failure == error.OutOfMemory) return failure;
            self.storage.events.appendAssumeCapacity(.{ .identity = identity, .outcome = .{ .failure = failure }, .work = before - call.remainingWork() });
            return failure;
        };
        errdefer result.release(call.allocator());
        const retained = try duplicate(self.allocator, call, result);
        self.storage.events.appendAssumeCapacity(.{ .identity = identity, .outcome = .{ .value = retained }, .work = before - call.remainingWork() });
        return result;
    }
};
fn duplicate(allocator: std.mem.Allocator, call: *host.Call, value: typed.Value) copy.Error!typed.Value {
    var copier: copy.Copier = .{ .records = call.records };
    return copier.copy(allocator, call.result_type, value);
}
fn invoke(call: *host.Call) host.CallbackError!typed.Value {
    const binding: *Binding = @ptrCast(@alignCast(call.context.?));
    const before = binding.tape.storage.events.items.len;
    return binding.tape.perform(binding, call) catch |failure| {
        if (!binding.tape.state.replaying and binding.tape.storage.events.items.len == before) binding.tape.state.failed = true;
        if (failure == error.HostReplayMismatch or failure == error.OutOfMemory) binding.tape.state.failed = true;
        return failure;
    };
}
fn fingerprint(hash: *Hash, value: typed.Value, depth: usize, visited: *usize) host.CallbackError!void {
    if (depth > 128 or visited.* == 65536) return error.HostWorkLimit;
    visited.* += 1;
    const ty: u64 = @intCast(@backingInt(value.typeOf()));
    hash.update(std.mem.asBytes(&ty));
    switch (value) {
        .i64 => |number| hash.update(std.mem.asBytes(&number)),
        .integer => |number| hash.update(std.mem.asBytes(&number.value)),
        .bool => |boolean| hash.update(&.{@intFromBool(boolean)}),
        .aggregate => |aggregate| {
            const count: u64 = aggregate.fields.len;
            const tag: u64 = if (aggregate.active_tag) |tag| tag else std.math.maxInt(u64);
            hash.update(std.mem.asBytes(&count));
            hash.update(std.mem.asBytes(&tag));
            for (aggregate.fields) |field| try fingerprint(hash, field, depth + 1, visited);
        },
        else => return error.HostReplayMismatch,
    }
}

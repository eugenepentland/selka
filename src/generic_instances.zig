//! Compilation-local specialization identities, independent of executable function indexes.
const std = @import("std");
const typed = @import("typed.zig");
/// Ordinal of an already-resolved declaration in the linked syntax program.
pub const DeclarationId = enum(usize) { _ };
/// Stable ordinal assigned when a concrete specialization is first discovered.
pub const InstanceId = enum(usize) { _ };
/// Resolved declaration and ordered concrete type identities; names and layouts are not keys.
pub const Key = struct {
    declaration: DeclarationId,
    arguments: []const typed.Type,
    lengths: []const ?usize = &.{},
    /// Read a constant argument value; ordinary type arguments have no scalar length.
    pub fn length(self: Key, index: usize) ?usize {
        return if (self.lengths.len == 0) null else self.lengths[index];
    }
};
const Context = struct {
    /// Hash declaration and ordered identities without borrowing pointer identity.
    pub fn hash(_: Context, key: Key) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, key.declaration);
        std.hash.autoHash(&hasher, key.arguments.len);
        for (key.arguments, 0..) |argument, i| {
            std.hash.autoHash(&hasher, argument);
            std.hash.autoHash(&hasher, key.length(i));
        }
        return hasher.final();
    }
    /// Compare resolved identities; nominal layout equivalence does not merge keys.
    pub fn eql(_: Context, a: Key, b: Key) bool {
        if (a.declaration != b.declaration or !std.mem.eql(typed.Type, a.arguments, b.arguments)) return false;
        for (a.arguments, 0..) |_, i| if (a.length(i) != b.length(i)) return false;
        return true;
    }
};
const Index = std.HashMapUnmanaged(Key, InstanceId, Context, std.hash_map.default_max_load_percentage);
/// Owns a bounded append-only discovery table. Retain IDs, not pointers into entries.
/// Callers resolve privacy, arity, requirements and valid type IDs before interning.
/// Repeated or recursive requests reuse the original ID without extending the worklist.
pub const Registry = struct {
    /// GENERIC-INSTANCE-BUDGET-1: the most instances one generic declaration
    /// may have. The bound is per declaration, so a program's total grows with
    /// its generic declarations while polymorphic recursion, which multiplies
    /// the instances of one declaration, still stops.
    pub const max_instances = 4096;
    /// The most type arguments one instance may have.
    pub const max_arguments = 16;
    entries: std.ArrayList(Key) = .empty,
    index: Index = .empty,
    /// How many instances each declaration has.
    counts: std.AutoHashMapUnmanaged(DeclarationId, usize) = .empty,
    /// Release all owned argument copies and index storage using the insertion allocator.
    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
        for (self.entries.items) |key| {
            allocator.free(key.arguments);
            allocator.free(key.lengths);
        }
        self.entries.deinit(allocator);
        self.index.deinit(allocator);
        self.counts.deinit(allocator);
        self.* = .{};
    }
    /// Intern a resolved key transactionally. Allocation failure preserves IDs and contents.
    /// Empty arguments represent an ordinary function in the same eventual discovery queue.
    pub fn intern(self: *Registry, allocator: std.mem.Allocator, key: Key) error{ OutOfMemory, TooManyInstances, TooManyTypeArguments }!InstanceId {
        if (key.lengths.len != 0 and key.lengths.len != key.arguments.len) return error.TooManyTypeArguments;
        if (key.arguments.len > max_arguments) return error.TooManyTypeArguments;
        if (self.index.get(key)) |id| return id;
        if ((self.counts.get(key.declaration) orelse 0) == max_instances) return error.TooManyInstances;
        try self.entries.ensureUnusedCapacity(allocator, 1);
        try self.index.ensureUnusedCapacity(allocator, 1);
        try self.counts.ensureUnusedCapacity(allocator, 1);
        const lengths = try allocator.dupe(?usize, key.lengths);
        errdefer allocator.free(lengths);
        const owned: Key = .{ .declaration = key.declaration, .arguments = try allocator.dupe(typed.Type, key.arguments), .lengths = lengths };
        const id: InstanceId = @fromBackingInt(self.entries.items.len);
        self.entries.appendAssumeCapacity(owned);
        self.index.putAssumeCapacityNoClobber(owned, id);
        const count = self.counts.getOrPutAssumeCapacity(key.declaration);
        count.value_ptr.* = if (count.found_existing) count.value_ptr.* + 1 else 1;
        return id;
    }
    /// Read a previously assigned identity. Argument storage survives later insertions.
    pub fn get(self: *const Registry, id: InstanceId) error{InvalidInstance}!Key {
        if (@backingInt(id) >= self.entries.items.len) return error.InvalidInstance;
        return self.entries.items[@backingInt(id)];
    }
};

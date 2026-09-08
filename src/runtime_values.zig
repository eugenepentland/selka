//! Immutable ordinary aggregates and unique owned records with field transfer.
//! Every VM operand/local owns one retained value.
const std = @import("std");
const external_resources = @import("external_resources.zig");
const runtime_values = @This();
/// Scalar and nominal type identities shared by checked syntax and runtime values.
pub const Type = enum(usize) {
    i64,
    bool,
    i8,
    i16,
    i32,
    u8,
    u16,
    u32,
    u64,
    allocator,
    clock_cap,
    random_cap,
    filesystem_cap,
    network_cap,
    environment_cap,
    unit,
    _,
    pub const record_base: usize = 16;
    /// Return the compact builtin capability index, or null for non-capabilities.
    pub fn capabilityIndex(self: Type) ?u3 {
        return switch (self) {
            .allocator => 0,
            .clock_cap => 1,
            .random_cap => 2,
            .filesystem_cap => 3,
            .network_cap => 4,
            .environment_cap => 5,
            else => null,
        };
    }
    /// Return the external resource family represented by this builtin type.
    pub fn resourceKind(self: Type) ?external_resources.Kind {
        return switch (self) {
            .filesystem_cap => .filesystem,
            .network_cap => .network,
            else => null,
        };
    }
    /// Return the clock or random provider family represented by this type.
    pub fn externalKind(self: Type) ?@import("external_capabilities.zig").Kind {
        return switch (self) {
            .clock_cap => .clock,
            .random_cap => .random,
            else => null,
        };
    }
    /// Integer width and signedness used for range checks and native layout.
    pub const Integer = struct { bits: u7, signed: bool };
    /// Return integer width and signedness, or null for other types.
    pub fn integer(self: Type) ?Integer {
        return switch (self) {
            .i8 => .{ .bits = 8, .signed = true },
            .i16 => .{ .bits = 16, .signed = true },
            .i32 => .{ .bits = 32, .signed = true },
            .i64 => .{ .bits = 64, .signed = true },
            .u8 => .{ .bits = 8, .signed = false },
            .u16 => .{ .bits = 16, .signed = false },
            .u32 => .{ .bits = 32, .signed = false },
            .u64 => .{ .bits = 64, .signed = false },
            else => null,
        };
    }
    /// Identify builtin signed and unsigned integer types.
    pub fn isInteger(self: Type) bool {
        return self.integer() != null;
    }
    /// Identify a nominal aggregate identity rather than a builtin scalar.
    pub fn isAggregate(self: Type) bool {
        return @backingInt(self) >= record_base;
    }
    /// Convert a nominal type identity into its schema table index.
    pub fn recordIndex(self: Type) usize {
        return @backingInt(self) - record_base;
    }
    /// Return the mathematical lower bound for this integer type.
    pub fn min(self: Type) i128 {
        const info = self.integer().?;
        return if (info.signed) -(@as(i128, 1) << (info.bits - 1)) else 0;
    }
    /// Return the mathematical upper bound for this integer type.
    pub fn max(self: Type) i128 {
        const info = self.integer().?;
        return (@as(i128, 1) << (info.bits - @as(u7, if (info.signed) 1 else 0))) - 1;
    }
    /// Check whether a mathematical integer lies within this type's bounds.
    pub fn fits(self: Type, value: i128) bool {
        return value >= self.min() and value <= self.max();
    }
    /// Canonical external decimal spelling shared by manifests and codecs.
    /// Language source literals have their own lexer and may use width suffixes.
    pub fn parseDecimal(self: Type, text: []const u8) error{ InvalidInteger, IntegerOutOfRange }!i128 {
        if (!self.isInteger() or text.len == 0 or text.len > 20) return error.InvalidInteger;
        const negative = text[0] == '-';
        const digits = text[@intFromBool(negative)..];
        if (digits.len == 0 or (digits[0] == '0' and (digits.len != 1 or negative))) return error.InvalidInteger;
        for (digits) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidInteger;
        const value = std.fmt.parseInt(i128, text, 10) catch return error.InvalidInteger;
        if (!self.fits(value)) return error.IntegerOutOfRange;
        return value;
    }
    /// Resolve a builtin type spelling without consulting nominal schemas.
    pub fn fromName(name: []const u8) ?Type {
        return std.meta.stringToEnum(Type, name);
    }
    pub fn format(self: Type, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.isAggregate()) try writer.print("type#{d}", .{@backingInt(self)}) else try writer.writeAll(@tagName(self));
    }
};

/// Runtime scalar, aggregate, capability, or owned resource representation.
pub const Value = union(enum) {
    unit,
    i64: i64,
    bool: bool,
    integer: struct { ty: Type, value: i128 },
    aggregate: *Aggregate,
    owned: OwnedValue,
    handle: struct { ty: Type, id: Pools.Id },
    capability: CapabilityValue,

    /// Return the scalar or nominal type carried by this value.
    pub fn typeOf(self: Value) Type {
        return switch (self) {
            .owned => |owned| owned.typeOf(),
            .capability => |capability| capability.typeOf(),
            .handle => |handle| handle.ty,
            .unit => .unit,
            .i64 => .i64,
            .bool => .bool,
            .integer => |n| n.ty,
            .aggregate => |record| record.ty,
        };
    }

    /// Test an owned-resource category without reading an inactive union field.
    pub fn isOwned(self: Value, kind: std.meta.Tag(OwnedValue)) bool {
        return self == .owned and self.owned == kind;
    }
    /// Test an authority category without reading an inactive union field.
    pub fn isCapability(self: Value, kind: std.meta.Tag(CapabilityValue)) bool {
        return self == .capability and self.capability == kind;
    }

    /// Construct the representation of a previously range-checked integer.
    pub fn number(ty: Type, value: i128) Value {
        std.debug.assert(ty.isInteger());
        std.debug.assert(ty.fits(value));
        return if (ty == .i64) .{ .i64 = @intCast(value) } else .{ .integer = .{ .ty = ty, .value = value } };
    }
    /// Extract a mathematical integer, rejecting noninteger representations.
    pub fn asInteger(self: Value) error{InternalError}!i128 {
        return switch (self) {
            .i64 => |n| n,
            .integer => |n| n.value,
            else => error.InternalError,
        };
    }
    /// Borrow input fields; the returned value owns independent references.
    pub fn create(allocator: std.mem.Allocator, ty: Type, fields: []const Value) error{ OutOfMemory, InvalidAggregateType }!Value {
        if (!ty.isAggregate()) return error.InvalidAggregateType;
        const record = try allocator.create(Aggregate);
        errdefer allocator.destroy(record);
        const owned = try allocator.alloc(Value, fields.len);
        for (fields, owned) |field, *out| out.* = field.retain();
        record.* = .{ .ty = ty, .fields = owned };
        return .{ .aggregate = record };
    }

    /// Allocate a nominal variant and retain its optional payload.
    pub fn createVariant(allocator: std.mem.Allocator, ty: Type, tag: usize, payload: ?Value) error{ OutOfMemory, InvalidAggregateType }!Value {
        const value = try create(allocator, ty, if (payload) |input| &.{input} else &.{});
        value.aggregate.active_tag = tag;
        return value;
    }
    /// Read a variant's active tag, rejecting nonvariant values.
    pub fn variantTag(self: Value) error{InternalError}!usize {
        if (self != .aggregate) return error.InternalError;
        return self.aggregate.active_tag orelse error.InternalError;
    }

    /// Input expressions are already evaluated in source order. Store in schema order.
    /// The emitter validates that order is a permutation before dispatch.
    pub fn createOrdered(allocator: std.mem.Allocator, ty: Type, fields: []const Value, order: []const usize) error{ OutOfMemory, InvalidAggregateType, InternalError }!Value {
        if (order.len == 0) return create(allocator, ty, fields);
        if (!ty.isAggregate() or order.len != fields.len) return error.InternalError;
        const record = try allocator.create(Aggregate);
        errdefer allocator.destroy(record);
        const owned = try allocator.alloc(Value, fields.len);
        for (fields, order) |field, index| owned[index] = field.retain();
        record.* = .{ .ty = ty, .fields = owned };
        return .{ .aggregate = record };
    }

    /// Allocate an aggregate snapshot with selected fields replaced, retaining unchanged fields.
    pub fn updated(self: Value, allocator: std.mem.Allocator, indices: []const usize, replacements: []const Value) error{ OutOfMemory, InvalidAggregateType, InternalError }!Value {
        if (self != .aggregate or self.aggregate.moved_fields != null or indices.len != replacements.len) return error.InternalError;
        for (indices) |index| if (index >= self.aggregate.fields.len) {
            return error.InternalError;
        };
        const out = try create(allocator, self.aggregate.ty, self.aggregate.fields);
        const fields = @constCast(out.aggregate.fields);
        for (indices, replacements) |index, replacement| {
            fields[index].release(allocator);
            fields[index] = replacement.retain();
        }
        return out;
    }

    /// Success consumes the external allocation handle; failure leaves it owned
    /// by the caller. Internal retained temporaries share one cleanup record.
    pub fn ownBuffer(allocator: std.mem.Allocator, ty: Type, store: *Memory.Store, owner: Memory.Allocation) (Memory.Error || std.mem.Allocator.Error)!Value {
        const resource = try allocator.create(Resource);
        errdefer allocator.destroy(resource);
        const moved = try store.transfer(owner);
        resource.* = .{ .ty = ty, .store = store, .owner = moved };
        return .{ .owned = .{ .resource = resource } };
    }
    /// Wrap an external owner in a reference-counted runtime value.
    pub fn ownExternal(allocator: std.mem.Allocator, ty: Type, store: *external_resources.Store, owner: external_resources.Owner) (external_resources.Error || std.mem.Allocator.Error)!Value {
        const resource = try allocator.create(ExternalResource);
        errdefer allocator.destroy(resource);
        const moved = try store.transfer(owner);
        resource.* = .{ .ty = ty, .store = store, .owner = moved };
        return .{ .owned = .{ .external_resource = resource } };
    }
    /// Add a reference to owned backing and return another value sharing it.
    pub fn retain(self: Value) Value {
        if (self == .owned) self.owned.retain();
        if (self == .aggregate) self.aggregate.references += 1;
        return self;
    }

    /// Release without allocation or recursive host calls. Zero-reference nodes
    /// temporarily form an intrusive work list; shared live nodes never change.
    pub fn release(self: Value, allocator: std.mem.Allocator) void {
        if (self != .aggregate and self != .owned) return;
        releaseManaged(self, allocator);
    }

    noinline fn releaseManaged(self: Value, allocator: std.mem.Allocator) void {
        var pending: ?*Aggregate = null;
        enqueueRelease(self, &pending, allocator);
        while (pending) |record| {
            if (record.release_index != 0) {
                record.release_index -= 1;
                if (record.moved_fields == null or !record.moved_fields.?[record.release_index]) enqueueRelease(record.fields[record.release_index], &pending, allocator);
            } else {
                pending = record.next;
                if (record.moved_fields) |moved| allocator.free(moved);
                allocator.free(record.fields);
                allocator.destroy(record);
            }
        }
    }

    fn enqueueRelease(value: Value, pending: *?*Aggregate, allocator: std.mem.Allocator) void {
        if (value == .owned) {
            value.owned.release(allocator);
            return;
        }
        if (value != .aggregate) return;
        const record = value.aggregate;
        std.debug.assert(record.references != 0);
        record.references -= 1;
        if (record.references == 0) {
            record.release_index = record.fields.len;
            record.next = pending.*;
            pending.* = record;
        }
    }

    /// Transfer one field from a unique aggregate without retaining it. Missing
    /// slots are tracked separately so cleanup never touches transferred values.
    /// Allocate bookkeeping before transfer; failure leaves the aggregate intact.
    pub fn takeField(self: Value, allocator: std.mem.Allocator, index: usize) error{ OutOfMemory, InternalError }!Value {
        if (self != .aggregate or self.aggregate.references != 1 or self.aggregate.active_tag != null or index >= self.aggregate.fields.len) return error.InternalError;
        const record = self.aggregate;
        if (record.moved_fields == null) {
            const moved = try allocator.alloc(bool, record.fields.len);
            @memset(moved, false);
            record.moved_fields = moved;
        }
        if (record.moved_fields.?[index]) return error.InternalError;
        record.moved_fields.?[index] = true;
        return record.fields[index];
    }

    /// Read and retain an initialized aggregate field, rejecting moved or missing fields.
    pub fn getField(self: Value, index: usize) error{InternalError}!Value {
        if (self != .aggregate or index >= self.aggregate.fields.len) return error.InternalError;
        if (self.aggregate.moved_fields) |moved| if (moved[index]) return error.InternalError;
        return self.aggregate.fields[index].retain();
    }
};

/// Reference-counted aggregate fields with variant and partial-move bookkeeping.
pub const Aggregate = struct {
    /// A moved slot contains a stale value representation and must never be read
    /// or released. Only the separately transferred owner may access that value.
    moved_fields: ?[]bool = null,
    active_tag: ?usize = null,
    ty: Type,
    fields: []const Value,
    references: usize = 1,
    next: ?*Aggregate = null,
    release_index: usize = 0,
};

/// Reference-counted wrapper for an owned guest memory allocation.
pub const Resource = struct { ty: Type, store: *Memory.Store, owner: Memory.Allocation, references: usize = 1 };

/// Reference-counted external owner; a null owner records completed or transferred ownership.
pub const ExternalResource = struct { ty: Type, store: *external_resources.Store, owner: ?external_resources.Owner, references: usize = 1 };

/// Inert environment authority tied to a single execution identity.
pub const EnvironmentCapability = struct { execution: u64 };
/// Pool element and handle identities shared by runtime operations and checked schemas.
pub const PoolSchema = struct { element: Type, handle: Type };

/// Checked guest allocation, borrowing, and region storage.
pub const Memory = struct {
    const regions = @import("regions.zig");
    const values = runtime_values;

    pub const Error = std.mem.Allocator.Error || error{
        IdentityExhausted,
        MemoryClosed,
        ForeignMemory,
        InvalidAllocation,
        ExpiredBorrow,
        BorrowConflict,
        BorrowSuspended,
        ChildrenActive,
        ReadOnly,
        Bounds,
        TypeMismatch,
        CapacityLimit,
        NoCapacity,
        InvalidCapability,
        RegionInUse,
    };
    /// Limits on guest allocation, aggregate capacity, and region registry growth.
    pub const Limits = struct {
        max_regions: usize = 256,
        max_buffer_capacity: usize = std.math.maxInt(usize) / @sizeOf(Value),
        max_total_capacity: usize = std.math.maxInt(usize) / @sizeOf(Value),
        max_allocations: usize = std.math.maxInt(usize),
    };
    /// Current backing usage and cumulative guest owner lifecycle counters.
    pub const Statistics = struct { live_allocations: usize = 0, total_capacity: usize = 0, created: u64 = 0, released: u64 = 0, transfers: u64 = 0, peak_capacity: usize = 0, peak_allocations: usize = 0 };
    /// Element type, initialized length, and reserved capacity of a live allocation.
    pub const BufferInfo = struct { element_type: Type, length: usize, capacity: usize };
    /// Whether a reservation required replacement backing storage.
    pub const Growth = enum { unchanged, allocated };
    /// Shared or exclusive dynamic borrow access.
    pub const Kind = enum { shared, exclusive };
    /// Registry slot plus generation, preventing stale identities from matching reused slots.
    pub const Token = struct { index: usize, generation: u64 };
    /// Execution-local allocator authority optionally limited to a live region.
    pub const AllocatorCapability = struct {
        memory: u64,
        // Issued region pool identities are nonzero. The all-zero handle encodes
        // root authority without an additional optional tag in every guest value.
        region_id: regions.Id = .{ .pool = 0, .index = 0, .generation = 0 },

        /// Decode root authority or the issued region identity carried by the grant.
        pub fn region(self: AllocatorCapability) ?regions.Id {
            return if (self.region_id.pool == 0) null else self.region_id;
        }
    };
    /// Retained allocator backing and the region whose lifetime it extends.
    pub const BackingLease = struct { allocator: std.mem.Allocator, region: ?regions.Id };
    /// Execution-bound generation-checked identity of owned guest storage.
    pub const Allocation = struct { memory: u64, token: Token };
    /// Execution-bound generation-checked identity of a dynamic borrow lease.
    pub const Borrow = struct { memory: u64, token: Token };
    /// Validated borrow extent, access mode, element type, and underlying allocation.
    pub const Extent = struct { start: usize, length: usize };
    /// Two disjoint children created atomically from one exclusive lease.
    pub const Split = struct { left: Borrow, right: Borrow };
    /// Validated allocation extent and optional authorized array member projection.
    pub const View = struct { projection: ?Extent = null, allocation: Allocation, start: usize, length: usize, kind: Kind, element_type: Type };

    const identities = @import("wiring/identity.zig");

    // Slots are reused only with a new generation. Exhausted generations retire
    // permanently; wrapping a generation would make an old handle valid again.
    fn Pool(comptime T: type) type {
        return struct {
            const Self = @This();
            const Entry = struct { generation: u64 = 1, value: ?T = null, next: ?usize = null };
            entries: std.ArrayList(Entry) = .empty,
            free_head: ?usize = null,

            fn insert(self: *Self, allocator: std.mem.Allocator, value: T) !Token {
                if (self.free_head) |index| {
                    const entry = &self.entries.items[index];
                    self.free_head = entry.next;
                    entry.next = null;
                    entry.value = value;
                    return .{ .index = index, .generation = entry.generation };
                }
                const index = self.entries.items.len;
                try self.entries.append(allocator, .{ .value = value });
                return .{ .index = index, .generation = 1 };
            }
            fn get(self: *Self, token: Token) ?*T {
                if (token.index >= self.entries.items.len) return null;
                const entry = &self.entries.items[token.index];
                if (entry.generation != token.generation) return null;
                return if (entry.value) |*value| value else null;
            }
            fn rekey(self: *Self, token: Token) Error!Token {
                const entry = &self.entries.items[token.index];
                std.debug.assert(entry.generation == token.generation);
                std.debug.assert(entry.value != null);
                if (entry.generation == std.math.maxInt(u64)) return error.IdentityExhausted;
                entry.generation += 1;
                return .{ .index = token.index, .generation = entry.generation };
            }
            fn remove(self: *Self, token: Token) T {
                const entry = &self.entries.items[token.index];
                std.debug.assert(entry.generation == token.generation);
                std.debug.assert(entry.value != null);
                const value = entry.value.?;
                entry.value = null;
                if (entry.generation != std.math.maxInt(u64)) {
                    entry.generation += 1;
                    entry.next = self.free_head;
                    self.free_head = token.index;
                }
                return value;
            }
        };
    }
    const Cell = struct { backing: BackingLease, element_type: Type, values: []Value, length: usize, shared: usize = 0, exclusive: bool = false };
    const Lease = struct { projection: ?Extent = null, allocation: Token, start: usize, length: usize, kind: Kind, parent: ?Token = null, children: usize = 0 };

    /// Owns memory/lease registries. Do not copy an initialized Store. Values passed
    /// to it use the same runtime allocator; successful reads return retained values.
    /// A Store is used by one VM execution thread. External pool owners and backing
    /// leases must release before deinit; their storage allocator points into the Store.
    pub const Store = struct {
        allocator: std.mem.Allocator,
        backing: struct {
            /// Set only before first allocation; outlives buffer storage.
            allocator: ?std.mem.Allocator = null,
            regions: regions.RegionStore,
            users: usize = 0,
        },
        identity: u64,
        limits: Limits = .{},
        statistics: Statistics = .{},
        cells: Pool(Cell) = .{},
        leases: Pool(Lease) = .{},

        /// Initialize a guest memory store with default capacity limits.
        pub fn init(allocator: std.mem.Allocator) Error!Store {
            var manager = try regions.RegionStore.init(allocator, 256);
            errdefer manager.deinit();
            return .{
                .allocator = allocator,
                .identity = try identities.acquire(),
                .backing = .{ .regions = manager },
            };
        }
        /// Called only by the embedding runtime; guest code cannot mint this value.
        pub fn allocatorCapability(self: *Store) Error!AllocatorCapability {
            try self.checkMemory(self.identity);
            return .{ .memory = self.identity };
        }
        /// Reject allocator authority from another execution or an expired region.
        pub fn checkAllocator(self: *Store, capability: AllocatorCapability) Error!void {
            if (self.identity == 0 or capability.memory != self.identity) return error.InvalidCapability;
            if (capability.region_id.pool == 0) {
                if (capability.region_id.index != 0 or capability.region_id.generation != 0) return error.InvalidCapability;
            }
            if (capability.region()) |region| try self.backing.regions.check(region);
        }
        /// Initialize a fresh memory identity and bounded allocation/lease registries.
        pub fn initWithLimits(allocator: std.mem.Allocator, limits: Limits) Error!Store {
            var store = try init(allocator);
            store.limits = limits;
            store.backing.regions.registry.max_slots = limits.max_regions;
            return store;
        }
        /// Final execution cleanup releases cells even when a trap leaves active
        /// leases. Normal owner destruction uses destroy and refuses active borrows.
        pub fn deinit(self: *Store) void {
            if (self.identity == 0) return;
            for (self.cells.entries.items, 0..) |entry, index| if (entry.value != null) {
                const owned = self.cells.remove(.{ .index = index, .generation = entry.generation });
                self.releaseOwned(owned);
            };
            self.cells.entries.deinit(self.allocator);
            self.leases.entries.deinit(self.allocator);
            self.cells = .{};
            self.leases = .{};
            std.debug.assert(self.backing.users == 0);
            self.backing.regions.deinit();
            self.identity = 0;
        }
        fn backingAllocator(self: *Store) std.mem.Allocator {
            return self.backing.allocator orelse self.allocator;
        }
        /// Create a child allocation region under validated parent authority.
        pub fn beginRegion(self: *Store, parent: AllocatorCapability) Error!AllocatorCapability {
            try self.checkAllocator(parent);
            return .{ .memory = self.identity, .region_id = try self.backing.regions.begin(parent.region()) };
        }
        /// Reclaim unused region backing without invalidating the region capability.
        pub fn resetRegion(self: *Store, capability: AllocatorCapability) Error!void {
            try self.checkAllocator(capability);
            try self.backing.regions.reset(capability.region() orelse return error.InvalidCapability);
        }
        /// Close a region only after all owners and nested regions have released it.
        pub fn endRegion(self: *Store, capability: AllocatorCapability) Error!void {
            try self.checkAllocator(capability);
            try self.backing.regions.end(capability.region() orelse return error.InvalidCapability);
        }
        /// Retain backing for validated allocation authority until releaseBacking is called.
        pub fn acquireBacking(self: *Store, capability: AllocatorCapability) Error!BackingLease {
            try self.checkAllocator(capability);
            if (capability.region()) |region| return .{ .allocator = try self.backing.regions.retain(region), .region = region };
            if (self.backing.users == std.math.maxInt(usize)) return error.CapacityLimit;
            self.backing.users += 1;
            return .{ .allocator = self.backingAllocator(), .region = null };
        }
        /// Release a previously acquired region backing lease.
        pub fn releaseBacking(self: *Store, lease_backing: BackingLease) void {
            if (lease_backing.region) |region| self.backing.regions.release(region) else {
                std.debug.assert(self.backing.users != 0);
                self.backing.users -= 1;
            }
        }
        /// Verify that an allocation belongs to the supplied allocator authority.
        pub fn checkAllocationAllocator(self: *Store, allocation: Allocation, capability: AllocatorCapability) Error!void {
            try self.checkAllocator(capability);
            const owned = try self.cell(allocation);
            if (!std.meta.eql(owned.backing.region, capability.region())) return error.InvalidCapability;
        }
        /// Region boundary: reject every live borrow before changing any allocation.
        /// Retains registry capacity and allocator authority; old cell identities stay
        /// invalid across reuse. Payload snapshots use the runtime allocator and survive.
        pub fn reset(self: *Store) Error!void {
            try self.checkMemory(self.identity);
            var root_cells: usize = 0;
            for (self.cells.entries.items) |entry| if (entry.value) |owned| {
                try unborrowed(owned);
                if (owned.backing.region == null) root_cells += 1;
            };
            // A root pool or another externally retained backing lease must release
            // before resetting the execution arena. Do not partially clear buffers.
            if (self.backing.users != root_cells) return error.RegionInUse;
            var index = self.cells.entries.items.len;
            while (index != 0) {
                index -= 1;
                const entry = self.cells.entries.items[index];
                if (entry.value != null) self.releaseOwned(self.cells.remove(.{ .index = index, .generation = entry.generation }));
            }
        }
        fn checkMemory(self: *Store, identity: u64) error{ MemoryClosed, ForeignMemory }!void {
            if (self.identity == 0) return error.MemoryClosed;
            if (self.identity != identity) return error.ForeignMemory;
        }
        fn cell(self: *Store, allocation: Allocation) error{ MemoryClosed, ForeignMemory, InvalidAllocation }!*Cell {
            try self.checkMemory(allocation.memory);
            return self.cells.get(allocation.token) orelse error.InvalidAllocation;
        }
        fn lease(self: *Store, reference: Borrow) Error!*Lease {
            try self.checkMemory(reference.memory);
            const active = self.leases.get(reference.token) orelse return error.ExpiredBorrow;
            if (self.cells.get(active.allocation) == null) return error.InvalidAllocation;
            return active;
        }
        fn freeCell(self: *Store, owned: Cell) void {
            var i = owned.length;
            while (i != 0) {
                i -= 1;
                owned.values[i].release(self.allocator);
            }
            owned.backing.allocator.free(owned.values);
            self.releaseBacking(owned.backing);
        }
        fn releaseOwned(self: *Store, owned: Cell) void {
            self.statistics.live_allocations -= 1;
            self.statistics.total_capacity -= owned.values.len;
            self.statistics.released +|= 1;
            self.freeCell(owned);
        }
        fn capacityAllowed(self: *Store, capacity: usize, increase: usize) Error!void {
            if (capacity > self.limits.max_buffer_capacity) return error.CapacityLimit;
            if (capacity > std.math.maxInt(usize) / @sizeOf(Value)) return error.CapacityLimit;
            if (self.statistics.total_capacity > self.limits.max_total_capacity) return error.CapacityLimit;
            if (increase > self.limits.max_total_capacity - self.statistics.total_capacity) return error.CapacityLimit;
        }
        fn unborrowed(owned: Cell) Error!void {
            if (owned.shared != 0 or owned.exclusive) return error.BorrowConflict;
        }
        /// Retain homogeneous ordinary values; input ownership stays with the caller.
        pub fn create(self: *Store, element_type: Type, inputs: []const Value) Error!Allocation {
            return self.createWithCapacity(element_type, inputs, inputs.len);
        }
        /// Create owned storage with retained inputs and explicit spare capacity.
        pub fn createWithCapacity(self: *Store, element_type: Type, inputs: []const Value, capacity: usize) Error!Allocation {
            return self.createAuthorized(try self.allocatorCapability(), element_type, inputs, capacity);
        }
        /// Create storage under validated allocator authority and retain its input values.
        pub fn createAuthorized(self: *Store, capability: AllocatorCapability, element_type: Type, inputs: []const Value, capacity: usize) Error!Allocation {
            try self.checkAllocator(capability);
            if (inputs.len > capacity) return error.Bounds;
            for (inputs) |input| if (input.typeOf() != element_type) return error.TypeMismatch;
            try self.capacityAllowed(capacity, capacity);
            if (self.statistics.live_allocations >= self.limits.max_allocations) return error.CapacityLimit;
            const lease_backing = try self.acquireBacking(capability);
            const buffer = lease_backing.allocator.alloc(Value, capacity) catch |err| {
                self.releaseBacking(lease_backing);
                return err;
            };
            for (inputs, buffer[0..inputs.len]) |input, *output| output.* = input.retain();
            const owned: Cell = .{ .backing = lease_backing, .element_type = element_type, .values = buffer, .length = inputs.len };
            errdefer self.freeCell(owned);
            const token = try self.cells.insert(self.allocator, owned);
            self.statistics.live_allocations += 1;
            self.statistics.total_capacity += capacity;
            self.statistics.peak_capacity = @max(self.statistics.peak_capacity, self.statistics.total_capacity);
            self.statistics.peak_allocations = @max(self.statistics.peak_allocations, self.statistics.live_allocations);
            self.statistics.created +|= 1;
            return .{ .memory = self.identity, .token = token };
        }
        /// Return the type, initialized length, and capacity of a live owner.
        pub fn bufferInfo(self: *Store, allocation: Allocation) Error!BufferInfo {
            const owned = try self.cell(allocation);
            if (owned.exclusive) return error.BorrowConflict;
            return .{ .element_type = owned.element_type, .length = owned.length, .capacity = owned.values.len };
        }
        /// Consume the owner identity without allocating or copying buffer contents.
        /// Active borrows prevent transfer. A failed transfer leaves the old owner valid.
        pub fn transfer(self: *Store, allocation: Allocation) Error!Allocation {
            try unborrowed((try self.cell(allocation)).*);
            const token = try self.cells.rekey(allocation.token);
            self.statistics.transfers +|= 1;
            return .{ .memory = self.identity, .token = token };
        }
        /// Grow an unborrowed allocation when necessary, preserving its initialized values.
        pub fn reserve(self: *Store, allocation: Allocation, capacity: usize) Error!Growth {
            const owned = try self.cell(allocation);
            try unborrowed(owned.*);
            if (capacity <= owned.values.len) return .unchanged;
            const increase = capacity - owned.values.len;
            try self.capacityAllowed(capacity, increase);
            const grown = try owned.backing.allocator.alloc(Value, capacity);
            @memcpy(grown[0..owned.length], owned.values[0..owned.length]);
            // Transfer existing Value ownership; releasing the old elements here
            // would invalidate the moved snapshots in the new backing buffer.
            owned.backing.allocator.free(owned.values);
            owned.values = grown;
            self.statistics.total_capacity += increase;
            self.statistics.peak_capacity = @max(self.statistics.peak_capacity, self.statistics.total_capacity);
            return .allocated;
        }
        /// Append a typed value without allocating additional capacity.
        pub fn appendWithinCapacity(self: *Store, allocation: Allocation, value: Value) Error!void {
            const owned = try self.cell(allocation);
            try unborrowed(owned.*);
            if (value.typeOf() != owned.element_type) return error.TypeMismatch;
            if (owned.length == owned.values.len) return error.NoCapacity;
            owned.values[owned.length] = value.retain();
            owned.length += 1;
        }
        /// Change initialized length within capacity, releasing removed values or retaining fill values.
        pub fn resizeWithinCapacity(self: *Store, allocation: Allocation, length: usize, fill: Value) Error!void {
            const owned = try self.cell(allocation);
            try unborrowed(owned.*);
            if (length > owned.values.len) return error.NoCapacity;
            if (length > owned.length and fill.typeOf() != owned.element_type) return error.TypeMismatch;
            while (owned.length > length) {
                owned.length -= 1;
                owned.values[owned.length].release(self.allocator);
            }
            while (owned.length < length) {
                owned.values[owned.length] = fill.retain();
                owned.length += 1;
            }
        }
        /// Move one initialized value out, filling its slot with the last value.
        pub fn takeOwner(self: *Store, allocation: Allocation, index: usize) Error!Value {
            const owned = try self.cell(allocation);
            try unborrowed(owned.*);
            if (index >= owned.length) return error.Bounds;
            const value = owned.values[index];
            owned.length -= 1;
            if (index != owned.length) owned.values[index] = owned.values[owned.length];
            return value;
        }
        /// Shrink only; every removed value is released exactly once.
        pub fn truncateOwner(self: *Store, allocation: Allocation, length: usize) Error!void {
            const owned = try self.cell(allocation);
            try unborrowed(owned.*);
            if (length > owned.length) return error.Bounds;
            while (owned.length > length) {
                owned.length -= 1;
                owned.values[owned.length].release(self.allocator);
            }
        }
        /// Release an unborrowed owner and invalidate its registry identity.
        pub fn destroy(self: *Store, allocation: Allocation) Error!void {
            try unborrowed((try self.cell(allocation)).*);
            self.releaseOwned(self.cells.remove(allocation.token));
        }
        /// Terminal unwind only: invalidate all views before releasing this owner.
        /// Normal scope exit uses destroy and diagnoses outstanding borrows.
        pub fn destroyForUnwind(self: *Store, allocation: Allocation) error{ MemoryClosed, ForeignMemory, InvalidAllocation }!void {
            _ = try self.cell(allocation);
            for (self.leases.entries.items, 0..) |entry, index| if (entry.value) |lease_value| {
                if (std.meta.eql(lease_value.allocation, allocation.token)) _ = self.leases.remove(.{ .index = index, .generation = entry.generation });
            };
            self.releaseOwned(self.cells.remove(allocation.token));
        }
        /// Terminal cleanup accepts stale or already-closed owners without touching a
        /// replacement allocation. The result states whether a live owner was released.
        pub fn destroyIfLiveForUnwind(self: *Store, allocation: Allocation) bool {
            self.destroyForUnwind(allocation) catch return false;
            return true;
        }
        /// Root borrows currently conflict over the whole allocation, even for
        /// disjoint or empty ranges. Bounds are still narrowed on each view.
        pub fn borrow(self: *Store, allocation: Allocation, start: usize, length: usize, kind: Kind) Error!Borrow {
            const owned = try self.cell(allocation);
            try checkRange(owned.length, start, length);
            if (owned.exclusive or (kind == .exclusive and owned.shared != 0)) return error.BorrowConflict;
            if (kind == .shared and owned.shared == std.math.maxInt(usize)) return error.IdentityExhausted;
            const token = try self.leases.insert(self.allocator, .{ .allocation = allocation.token, .start = start, .length = length, .kind = kind });
            // Lease insertion cannot relocate cells. Commit the lock only on success.
            if (kind == .shared) owned.shared += 1 else owned.exclusive = true;
            return .{ .memory = self.identity, .token = token };
        }
        /// Narrow a live borrow. Exclusive parents are suspended until their child
        /// ends. Shared parents permit shared children and remain readable.
        pub fn reborrow(self: *Store, parent: Borrow, start: usize, length: usize, kind: Kind) Error!Borrow {
            const previous = (try self.lease(parent)).*;
            try usable(previous);
            if (previous.kind == .shared and kind == .exclusive) return error.ReadOnly;
            try checkRange(previous.length, start, length);
            if (previous.children == std.math.maxInt(usize)) return error.IdentityExhausted;
            const token = try self.leases.insert(self.allocator, .{ .allocation = previous.allocation, .start = previous.start + start, .length = length, .kind = kind, .parent = parent.token, .projection = previous.projection });
            // Insertion may relocate leases, so resolve the parent again by identity.
            self.leases.get(parent.token).?.children += 1;
            return .{ .memory = self.identity, .token = token };
        }
        /// Atomically partition one exclusive extent; failed insertion preserves parent access.
        pub fn split(self: *Store, parent: Borrow, start: usize, length: usize, middle: usize) Error!Split {
            const previous = (try self.lease(parent)).*;
            try usable(previous);
            if (previous.kind != .exclusive) return error.ReadOnly;
            if (previous.projection != null) return error.TypeMismatch;
            try checkRange(previous.length, start, length);
            if (middle > length) return error.Bounds;
            var left = previous;
            left.start += start;
            left.length = middle;
            var right = left;
            right.start += middle;
            right.length = length - middle;
            return self.partition(parent, left, right);
        }
        /// Partition logical members of a single boxed array without authorizing whole-value access.
        pub fn splitFields(self: *Store, parent: Borrow, start: usize, length: usize, middle: usize) Error!Split {
            const previous = (try self.lease(parent)).*;
            try usable(previous);
            if (previous.kind != .exclusive) return error.ReadOnly;
            const array = try self.fieldArray(previous);
            try checkRange(array.aggregate.fields.len, start, length);
            if (previous.projection) |extent| {
                if (start < extent.start) return error.Bounds;
                try checkRange(extent.length, start - extent.start, length);
            }
            if (middle > length) return error.Bounds;
            var left = previous;
            left.projection = .{ .start = start, .length = middle };
            var right = previous;
            right.projection = .{ .start = start + middle, .length = length - middle };
            return self.partition(parent, left, right);
        }
        fn partition(self: *Store, parent: Borrow, left: Lease, right: Lease) Error!Split {
            var first = left;
            first.parent = parent.token;
            var second = right;
            second.parent = parent.token;
            const left_token = try self.leases.insert(self.allocator, first);
            errdefer _ = self.leases.remove(left_token);
            const right_token = try self.leases.insert(self.allocator, second);
            self.leases.get(parent.token).?.children += 2;
            return .{ .left = .{ .memory = self.identity, .token = left_token }, .right = .{ .memory = self.identity, .token = right_token } };
        }
        /// End a live borrow and restore its parent's access when applicable.
        pub fn end(self: *Store, reference: Borrow) Error!void {
            const active = (try self.lease(reference)).*;
            if (active.children != 0) return error.ChildrenActive;
            _ = self.leases.remove(reference.token);
            if (active.parent) |parent| {
                self.leases.get(parent).?.children -= 1;
            } else {
                const owned = self.cells.get(active.allocation).?;
                if (active.kind == .shared) owned.shared -= 1 else owned.exclusive = false;
            }
        }
        /// Validate a borrow and return its allocation, bounds, type, and access mode.
        pub fn describe(self: *Store, reference: Borrow) Error!View {
            const active = (try self.lease(reference)).*;
            try usable(active);
            return .{
                .projection = active.projection,
                .allocation = .{ .memory = self.identity, .token = active.allocation },
                .start = active.start,
                .length = active.length,
                .kind = active.kind,
                .element_type = self.cells.get(active.allocation).?.element_type,
            };
        }
        /// Read and retain a value through an active in-bounds borrow.
        pub fn read(self: *Store, reference: Borrow, index: usize) Error!Value {
            const active = (try self.lease(reference)).*;
            try usable(active);
            if (active.projection != null) return error.TypeMismatch;
            if (index >= active.length) return error.Bounds;
            return self.cells.get(active.allocation).?.values[active.start + index].retain();
        }
        /// Replace a value through a live exclusive borrow after bounds and type checks.
        pub fn write(self: *Store, reference: Borrow, index: usize, replacement: Value) Error!void {
            const active = (try self.lease(reference)).*;
            try usable(active);
            if (active.projection != null) return error.TypeMismatch;
            if (active.kind != .exclusive) return error.ReadOnly;
            if (index >= active.length) return error.Bounds;
            try self.replace(self.cells.get(active.allocation).?, active.start + index, replacement);
        }
        fn fieldArray(self: *Store, active: Lease) Error!Value {
            if (active.length != 1) return error.TypeMismatch;
            const value = self.cells.get(active.allocation).?.values[active.start];
            if (value != .aggregate or value.aggregate.active_tag != null or value.aggregate.moved_fields != null) return error.TypeMismatch;
            return value;
        }
        fn fieldValue(self: *Store, reference: Borrow, index: usize, mutable: bool) Error!Value {
            const active = (try self.lease(reference)).*;
            try usable(active);
            if (mutable and active.kind != .exclusive) return error.ReadOnly;
            const value = try self.fieldArray(active);
            if (index >= value.aggregate.fields.len) return error.Bounds;
            if (active.projection) |extent| {
                if (index < extent.start or index - extent.start >= extent.length) return error.Bounds;
            }
            return value;
        }
        /// Read one copied member under both the logical partition and lease bounds.
        pub fn readField(self: *Store, reference: Borrow, index: usize) Error!Value {
            const value = try self.fieldValue(reference, index, false);
            return value.aggregate.fields[index].retain();
        }
        /// Replace one authorized member while preserving earlier aggregate snapshots.
        pub fn writeField(self: *Store, reference: Borrow, index: usize, replacement: Value) Error!void {
            const value = try self.fieldValue(reference, index, true);
            if (value.aggregate.fields[index].typeOf() != replacement.typeOf()) return error.TypeMismatch;
            const updated = value.updated(self.allocator, &.{index}, &.{replacement}) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.TypeMismatch,
            };
            defer updated.release(self.allocator);
            const active = (try self.lease(reference)).*;
            try self.replace(self.cells.get(active.allocation).?, active.start, updated);
        }
        /// Validate access to an owner cell without copying or changing its generation.
        pub fn checkOwnerAccess(self: *Store, allocation: Allocation, mutable: bool) Error!void {
            const owned = try self.cell(allocation);
            if (owned.exclusive or (mutable and owned.shared != 0)) return error.BorrowConflict;
        }
        /// Read and retain an owner element after checking dynamic borrow conflicts.
        pub fn readOwner(self: *Store, allocation: Allocation, index: usize) Error!Value {
            const owned = try self.cell(allocation);
            if (owned.exclusive) return error.BorrowConflict;
            if (index >= owned.length) return error.Bounds;
            return owned.values[index].retain();
        }
        /// Replace an owner element only when its borrow state permits mutation.
        pub fn writeOwner(self: *Store, allocation: Allocation, index: usize, replacement: Value) Error!void {
            const owned = try self.cell(allocation);
            if (owned.exclusive or owned.shared != 0) return error.BorrowConflict;
            if (index >= owned.length) return error.Bounds;
            try self.replace(owned, index, replacement);
        }
        fn replace(self: *Store, owned: *Cell, index: usize, replacement: Value) Error!void {
            if (replacement.typeOf() != owned.element_type) return error.TypeMismatch;
            const next = replacement.retain();
            owned.values[index].release(self.allocator);
            owned.values[index] = next;
        }
    };
    fn usable(lease: Lease) Error!void {
        if (lease.kind == .exclusive and lease.children != 0) return error.BorrowSuspended;
    }
    fn checkRange(capacity: usize, start: usize, length: usize) Error!void {
        // Subtraction avoids overflow in start + length, including hostile indices.
        if (start > capacity or length > capacity - start) return error.Bounds;
    }

    test "memory slot generations never wrap into stale handles" {
        var pool: Pool(u8) = .{};
        defer pool.entries.deinit(std.testing.allocator);
        const first = try pool.insert(std.testing.allocator, 7);
        pool.entries.items[first.index].generation = std.math.maxInt(u64);
        const last: Token = .{ .index = first.index, .generation = std.math.maxInt(u64) };
        try std.testing.expectEqual(@as(u8, 7), pool.remove(last));
        const next = try pool.insert(std.testing.allocator, 9);
        try std.testing.expect(next.index != last.index);
        try std.testing.expect(pool.get(first) == null and pool.get(last) == null);
    }

    test "exhausted ownership generations fail transfer without losing the buffer" {
        const t = std.testing;
        var store = try Store.init(t.allocator);
        defer store.deinit();
        const first = try store.create(.i64, &.{.{ .i64 = 7 }});
        store.cells.entries.items[first.token.index].generation = std.math.maxInt(u64);
        const last: Allocation = .{ .memory = first.memory, .token = .{ .index = first.token.index, .generation = std.math.maxInt(u64) } };
        try t.expectError(error.IdentityExhausted, store.transfer(last));
        try t.expectEqual(@as(i64, 7), (try store.readOwner(last, 0)).i64);
        try t.expectEqual(@as(u64, 0), store.statistics.transfers);
        try store.destroy(last);
        const next = try store.create(.i64, &.{});
        try t.expect(next.token.index != last.token.index);
        try t.expectError(error.InvalidAllocation, store.bufferInfo(last));
        try t.expect(!store.destroyIfLiveForUnwind(last));
        _ = try store.bufferInfo(next);
        try t.expect(store.destroyIfLiveForUnwind(next));
        try t.expect(!store.destroyIfLiveForUnwind(next));
        store.deinit();
        try t.expect(!store.destroyIfLiveForUnwind(next));
    }
};

/// Pool ownership and per-execution quota accounting.
pub const Pools = struct {
    const values = runtime_values;
    const memory = Memory;
    const backend = @import("typed_pool.zig");
    const SourceTag = struct {};
    pub const Registry = backend.Pool(SourceTag, values.Value);
    pub const Id = backend.Handle(SourceTag);
    /// Bounds on pool count, individual capacity, and total reserved slots.
    pub const Limits = struct { max_pools: usize = 64, max_pool_slots: usize = 4096, max_total_slots: usize = 16384 };
    /// Current pool backing usage and cumulative owner lifecycle counters.
    pub const Statistics = struct { live_pools: usize = 0, reserved_slots: usize = 0, acquired: u64 = 0, released: u64 = 0, peak_slots: usize = 0, peak_pools: usize = 0 };
    /// Owns typed pool registries and tracks their aggregate capacity limits.
    pub const Runtime = struct {
        allocator: std.mem.Allocator,
        limits: Limits,
        statistics: Statistics = .{},

        /// Allocate a typed pool owner under the runtime's capacity limits.
        pub fn acquire(self: *Runtime, ty: values.Type, capacity: usize) backend.Error!values.Value {
            return self.acquireBacking(ty, capacity, self.allocator, null, null);
        }
        /// Allocate a pool using validated guest allocator authority and retain its backing lease.
        pub fn acquireAuthorized(self: *Runtime, ty: values.Type, capacity: usize, store: *memory.Store, capability: memory.AllocatorCapability) (memory.Error || backend.Error)!values.Value {
            const backing = try store.acquireBacking(capability);
            errdefer store.releaseBacking(backing);
            return self.acquireBacking(ty, capacity, backing.allocator, store, backing);
        }
        fn acquireBacking(self: *Runtime, ty: values.Type, capacity: usize, backing_allocator: std.mem.Allocator, store: ?*memory.Store, backing: ?memory.BackingLease) backend.Error!values.Value {
            if (self.statistics.live_pools >= self.limits.max_pools or capacity > self.limits.max_pool_slots or capacity > self.limits.max_total_slots - self.statistics.reserved_slots) return error.CapacityLimit;
            const owner = try self.allocator.create(Owner);
            errdefer self.allocator.destroy(owner);
            owner.* = .{ .ty = ty, .runtime = self, .backing_store = store, .backing = backing, .registry = try Registry.init(backing_allocator, capacity, .{ .retain = values.Value.retain, .release = values.Value.release }) };
            owner.registry.value_allocator = self.allocator;
            errdefer owner.registry.deinit();
            try owner.registry.reserve(capacity);
            self.statistics.live_pools += 1;
            self.statistics.reserved_slots += capacity;
            self.statistics.peak_slots = @max(self.statistics.peak_slots, self.statistics.reserved_slots);
            self.statistics.peak_pools = @max(self.statistics.peak_pools, self.statistics.live_pools);
            self.statistics.acquired +|= 1;
            return .{ .owned = .{ .pool = owner } };
        }
    };
    /// Reference-counted typed pool ownership and optional retained region backing.
    pub const Owner = struct {
        ty: values.Type,
        runtime: *Runtime,
        registry: Registry,
        references: usize = 1,
        backing_store: ?*memory.Store = null,
        backing: ?memory.BackingLease = null,

        /// Borrows arguments; success returns one owned snapshot or inert scalar/ID.
        pub fn perform(self: *Owner, kind: @import("pool_operations.zig").Kind, schema: PoolSchema, arguments: []const values.Value) (backend.Error || error{InternalError})!values.Value {
            if (arguments.len != kind.arity()) return error.InternalError;
            for (arguments, 0..) |argument, index| {
                if (argument.typeOf() != (if (kind == .insert or index == 1) schema.element else schema.handle)) return error.InternalError;
            }
            switch (kind) {
                .length => return values.Value.number(.u64, self.registry.statistics.live),
                .capacity => return values.Value.number(.u64, self.registry.max_slots),
                .clear => {
                    try self.registry.clear();
                    return .{ .bool = true };
                },
                .insert => return .{ .handle = .{ .ty = schema.handle, .id = try self.registry.insert(arguments[0]) } },
                .read, .replace, .remove => {
                    if (arguments[0] != .handle) return error.InternalError;
                    const id = arguments[0].handle.id;
                    switch (kind) {
                        .read => return self.registry.get(id),
                        .replace => try self.registry.replace(id, arguments[1]),
                        .remove => try self.registry.remove(id),
                        else => unreachable,
                    }
                    return .{ .bool = true };
                },
            }
        }

        /// Drop a pool owner reference and reclaim its registry/backing at the final release.
        pub fn release(self: *Owner) void {
            std.debug.assert(self.references != 0);
            self.references -= 1;
            if (self.references != 0) return;
            const runtime = self.runtime;
            const capacity = self.registry.max_slots;
            self.registry.deinit();
            if (self.backing_store) |store| store.releaseBacking(self.backing.?);
            runtime.statistics.live_pools -= 1;
            runtime.statistics.reserved_slots -= capacity;
            runtime.statistics.released +|= 1;
            runtime.allocator.destroy(self);
        }
    };
};

/// Resource categories whose retained wrappers own a runtime cleanup obligation.
pub const OwnedValue = union(enum) {
    resource: *Resource,
    external_resource: *ExternalResource,
    pool: *Pools.Owner,

    fn typeOf(self: OwnedValue) Type {
        return switch (self) {
            .resource => |resource| resource.ty,
            .external_resource => |resource| resource.ty,
            .pool => |pool| pool.ty,
        };
    }
    fn retain(self: OwnedValue) void {
        switch (self) {
            .resource => |resource| resource.references += 1,
            .external_resource => |resource| resource.references += 1,
            .pool => |pool| pool.references += 1,
        }
    }
    fn release(self: OwnedValue, allocator: std.mem.Allocator) void {
        if (self == .pool) {
            self.pool.release();
            return;
        }
        if (self == .external_resource) {
            const resource = self.external_resource;
            std.debug.assert(resource.references != 0);
            resource.references -= 1;
            if (resource.references == 0) {
                if (resource.owner) |owner| _ = resource.store.releaseIfLive(owner);
                allocator.destroy(resource);
            }
            return;
        }
        if (self == .resource) {
            const resource = self.resource;
            std.debug.assert(resource.references != 0);
            resource.references -= 1;
            if (resource.references == 0) {
                _ = resource.store.destroyIfLiveForUnwind(resource.owner);
                allocator.destroy(resource);
            }
            return;
        }
    }
};

/// Inert grants whose authority is checked by their associated execution store.
pub const CapabilityValue = union(enum) {
    environment_capability: EnvironmentCapability,
    resource_capability: external_resources.Capability,
    allocator: Memory.AllocatorCapability,
    external: @import("external_capabilities.zig").Capability,

    fn typeOf(self: CapabilityValue) Type {
        return switch (self) {
            .allocator => .allocator,
            .environment_capability => .environment_cap,
            .resource_capability => |cap| if (cap.kind == .filesystem) .filesystem_cap else .network_cap,
            .external => |cap| switch (cap.kind) {
                .clock => .clock_cap,
                .random => .random_cap,
            },
        };
    }
};

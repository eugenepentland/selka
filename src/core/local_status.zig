//! What the ownership pass decided about each named local of a function (W2): whether it owns its value or borrows it,
//! and from which named places. `selka dump-typed` prints it beside each local, so a reader can ask the tool instead of
//! re-deriving the three whole-function tables of `single_owner.zig` (`borrowedMutLocals`, `BorrowedRecords`,
//! `BorrowedCollections`) by hand. It reads the same tables the checker and lowering read; it decides nothing.
const std = @import("std");
const typed = @import("selka").typed;
const typed_walk = @import("selka").typed_walk;
const single_owner = @import("single_owner.zig");

/// How a local holds its value.
pub const Holding = enum {
    /// A scalar or a lowering temporary: nothing to say.
    none,
    /// It owns its value and destroys it.
    owns,
    /// A plain parameter: a read-only borrow of the caller's value.
    caller,
    /// A `mut` parameter: an exclusive borrow of the caller's storage.
    caller_mut,
    /// It borrows its value from `lenders` (a `const` alias of a place, a loop variable, a `mut` local of 4f).
    borrows,
    /// A record built from borrowed fields (1A): it borrows its fields from `lenders`.
    fields,
    /// A list of borrows (RB2): it owns its buffer and borrows its elements from `lenders`.
    elements,
};

/// One local's status: how it holds its value and the named locals it borrows from, in slot order.
pub const Status = struct { holding: Holding = .none, lenders: []const usize = &.{} };

/// The status of every local of `function`, indexed by slot and allocated in `a` (an arena).
pub fn of(a: std.mem.Allocator, program: typed.Program, function: typed.Function) error{OutOfMemory}![]Status {
    const locals = function.scope.locals;
    const out = try a.alloc(Status, locals.len);
    @memset(out, .{});
    const linear = try single_owner.ownedTypesOf(a, program);
    const payloads = try single_owner.BorrowedRecords.casePayloads(a, program);
    const borrowed_mut = try single_owner.borrowedMutLocals(a, program, linear, function, payloads);
    const collections = try single_owner.BorrowedCollections.init(a, program, linear, function, payloads, &.{});
    const records = try single_owner.BorrowedRecords.init(a, program, linear, function, payloads);
    var finder: Finder = .{ .a = a, .program = program, .function = function, .records = records };
    try finder.index();
    for (locals, out, 0..) |local, *status, slot| {
        if (!single_owner.namedLocal(local) or !single_owner.isOwned(linear, local.ty)) continue;
        if (slot < function.signature.parameter_count) {
            const own = slot < function.scope.own_parameters.len and function.scope.own_parameters[slot];
            status.holding = if (own) .owns else if (local.mutable) .caller_mut else .caller;
            continue;
        }
        status.* = try finder.decide(slot, collections.holds(slot), borrowed_mut[slot]);
    }
    return out;
}

/// The values stored or appended to each local, by slot.
const Values = std.AutoHashMapUnmanaged(usize, std.ArrayList(typed.NodeId));

/// The stores and match bindings of one function, and the roots of the places they read.
const Finder = struct {
    a: std.mem.Allocator,
    program: typed.Program,
    function: typed.Function,
    records: single_owner.BorrowedRecords,
    /// Every value stored to each local, in source order (initializers and assignments).
    stores: Values = .empty,
    /// Every value appended to each local list, read through the receiver temporary that stages it.
    appends: Values = .empty,
    /// The scrutinee of the match that binds each payload local.
    matched: std.AutoHashMapUnmanaged(usize, typed.NodeId) = .empty,

    fn index(self: *Finder) error{OutOfMemory}!void {
        var walker = try typed_walk.Walker.init(self.a, self.program, self.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .statement => |id| switch (self.program.statements[@backingInt(id)].data) {
                .initialize, .assign => |store| try add(self.a, &self.stores, @backingInt(store.slot), store.value),
                .match => |match| if (!self.program.nodes[@backingInt(match.value)].own) for (match.arms) |arm| {
                    if (arm.slot) |bound| try self.matched.put(self.a, @backingInt(bound), match.value);
                },
                else => {},
            },
            .expression => |id| {
                const node = self.program.nodes[@backingInt(id)];
                if (node.data != .buffer_operation) continue;
                const operation = node.data.buffer_operation;
                if (operation.kind != .append or operation.arguments.len != 1) continue;
                const owner = self.named(@backingInt(operation.owner)) orelse continue;
                try add(self.a, &self.appends, owner, operation.arguments[0]);
            },
        };
    }

    fn add(a: std.mem.Allocator, map: *Values, slot: usize, value: typed.NodeId) error{OutOfMemory}!void {
        const entry = try map.getOrPut(a, slot);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(a, value);
    }

    /// The status of declared local `slot`, given whether it is a borrowed collection and a borrowed `mut` local.
    fn decide(self: *Finder, slot: usize, collection: bool, borrowed_mut: bool) error{OutOfMemory}!Status {
        var lenders: std.ArrayList(usize) = .empty;
        if (collection) {
            for (self.listed(self.appends, slot)) |value| try self.rootsOf(value, &lenders, 0);
            return .{ .holding = .elements, .lenders = try self.sorted(&lenders) };
        }
        const local = self.function.scope.locals[slot];
        const stores = self.listed(self.stores, slot);
        if (borrowed_mut) {
            for (stores) |value| try self.rootsOf(value, &lenders, 0);
            return .{ .holding = .borrows, .lenders = try self.sorted(&lenders) };
        }
        if (self.matched.get(slot)) |scrutinee| {
            try self.rootsOf(scrutinee, &lenders, 0);
            return .{ .holding = .borrows, .lenders = try self.sorted(&lenders) };
        }
        if (local.mutable or stores.len != 1) return .{ .holding = .owns };
        const value = stores[0];
        const node = self.program.nodes[@backingInt(value)];
        if (node.own) return .{ .holding = .owns };
        if (node.data == .record) {
            if (!self.records.constructor(value)) return .{ .holding = .owns };
            try self.rootsOf(value, &lenders, 0);
            return .{ .holding = .fields, .lenders = try self.sorted(&lenders) };
        }
        const place = single_owner.constBorrowPlace(self.program, self.function, value) orelse
            single_owner.slicePlace(self.program, self.function, value) orelse return .{ .holding = .owns };
        try self.rootsAt(@backingInt(place), &lenders, 0);
        return .{ .holding = .borrows, .lenders = try self.sorted(&lenders) };
    }

    fn listed(self: *const Finder, map: Values, slot: usize) []const typed.NodeId {
        _ = self;
        return if (map.get(slot)) |values| values.items else &.{};
    }

    /// Add the named locals the place or borrowed value `value` reads: each borrowed field of a record, the payload of an
    /// option, else the root of the place. A fresh value adds nothing.
    fn rootsOf(self: *Finder, value: typed.NodeId, out: *std.ArrayList(usize), depth: usize) error{OutOfMemory}!void {
        if (depth > 16) return;
        const node = self.program.nodes[@backingInt(value)];
        if (node.own) return;
        switch (node.data) {
            .record => |fields| for (fields) |field| try self.rootsOf(field.value, out, depth + 1),
            .variant => |variant| if (variant.value) |payload| try self.rootsOf(payload, out, depth + 1),
            else => {
                const place = single_owner.constBorrowPlace(self.program, self.function, value) orelse
                    single_owner.slicePlace(self.program, self.function, value) orelse return;
                try self.rootsAt(@backingInt(place), out, depth + 1);
            },
        }
    }

    /// Add the owners local `slot` stands for: itself when the source names it and it owns or is a parameter; what it borrows
    /// from when it is a `const` alias, a loop variable or a match binding; what a lowering temporary was initialized from.
    fn rootsAt(self: *Finder, slot: usize, out: *std.ArrayList(usize), depth: usize) error{OutOfMemory}!void {
        if (slot >= self.function.scope.locals.len or depth > 16) return;
        const local = self.function.scope.locals[slot];
        if (single_owner.namedLocal(local) and !self.alias(slot)) {
            if (std.mem.indexOfScalar(usize, out.items, slot) == null) try out.append(self.a, slot);
            return;
        }
        if (self.matched.get(slot)) |scrutinee| return self.rootsOf(scrutinee, out, depth + 1);
        for (self.listed(self.stores, slot)) |value| try self.rootsOf(value, out, depth + 1);
    }

    /// Whether named local `slot` only borrows what it reads: a match binding, or a `const` (a loop variable included) stored
    /// once from a place without `own`. Its lenders are then the owners of that place.
    fn alias(self: *const Finder, slot: usize) bool {
        if (slot < self.function.signature.parameter_count) return false;
        if (self.matched.contains(slot)) return true;
        const local = self.function.scope.locals[slot];
        const stores = self.listed(self.stores, slot);
        if (local.mutable or stores.len != 1 or self.program.nodes[@backingInt(stores[0])].own) return false;
        return single_owner.constBorrowPlace(self.program, self.function, stores[0]) != null or
            single_owner.slicePlace(self.program, self.function, stores[0]) != null;
    }

    /// The named local a list operation's owner stands for, read through its receiver temporary.
    fn named(self: *const Finder, slot: usize) ?usize {
        if (slot >= self.function.scope.locals.len) return null;
        if (single_owner.namedLocal(self.function.scope.locals[slot])) return slot;
        const stored = self.listed(self.stores, slot);
        if (stored.len != 1) return null;
        const read = self.program.nodes[@backingInt(stored[0])];
        if (read.data != .local or read.own) return null;
        const source = @backingInt(read.data.local);
        if (source >= self.function.scope.locals.len or !single_owner.namedLocal(self.function.scope.locals[source])) return null;
        return source;
    }

    fn sorted(self: *const Finder, lenders: *std.ArrayList(usize)) error{OutOfMemory}![]const usize {
        _ = self;
        std.mem.sort(usize, lenders.items, {}, std.sort.asc(usize));
        return lenders.items;
    }
};

/// The text `dump-typed` prints after a local's type: ` owns`, ` borrows from a, b`, ` borrows elements from a`, and so on,
/// or nothing for a scalar or a lowering temporary.
pub fn render(a: std.mem.Allocator, function: typed.Function, status: Status) error{OutOfMemory}![]const u8 {
    const lead = switch (status.holding) {
        .none => return "",
        .owns => return " owns",
        .caller => return " borrows from the caller",
        .caller_mut => return " borrows mut from the caller",
        .borrows => " borrows from",
        .fields => " borrows fields from",
        .elements => " borrows elements from",
    };
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, lead);
    if (status.lenders.len == 0) try out.appendSlice(a, " a borrowed result");
    for (status.lenders, 0..) |slot, position| {
        try out.appendSlice(a, if (position == 0) " " else ", ");
        try out.appendSlice(a, function.scope.locals[slot].name);
    }
    return out.items;
}

//! PY-RANGE-STEP-1: the counting loop of `range(start, stop, step)`.
//!
//! A stepped range counts from `start` toward `stop` by `step`, upward for a
//! positive step and downward for a negative one, exactly as Python's `range`
//! does. The counter advances with a wrapping add and ends the loop when that
//! add leaves the counter's own integer type, so the final step never traps an
//! overflow Python could not have: the value it would have produced lies past
//! `stop` anyway. A literal zero step is rejected statically and a zero runtime
//! step traps before the first iteration, as Python raises before iterating.
const typed = @import("typed.zig");
const collections = @import("collection_lower.zig");
const diagnostic = @import("diagnostic.zig");

/// Diagnostic code for a `range` whose step is the literal zero.
pub const zero_code = "E_RANGE_STEP";
/// CPython's message for a zero step, used by the static rejection and by the
/// trap a zero runtime step raises.
pub const zero_message = "range() arg 3 must not be zero";

/// How one loop advances: by a step the checker knows, or by a runtime stride
/// held in an internal local after its zero check.
pub const Stride = union(enum) { constant: i128, slot: typed.LocalId };

/// The pieces of one stepped counting loop over a counter and its limit.
pub fn Lower(comptime Checker: type) type {
    return struct {
        b: collections.Builder(Checker),
        element: typed.Type,
        stride: Stride,

        const Self = @This();

        /// The stride as a checked value of the counter's type.
        fn step(self: Self) diagnostic.Error!typed.NodeId {
            return switch (self.stride) {
                .constant => |value| self.b.node(self.element, .{ .integer = value }),
                .slot => |slot| self.b.read(slot),
            };
        }
        fn zero(self: Self) diagnostic.Error!typed.NodeId {
            return self.b.node(self.element, .{ .integer = 0 });
        }
        /// `left op right` for two counter-typed values, answering `bool`.
        fn compare(self: Self, op: typed.BinaryOp, left: typed.NodeId, right: typed.NodeId) diagnostic.Error!typed.NodeId {
            return self.b.binary(op, left, right, .bool);
        }
        /// Choose between the ascending and the descending form of one test:
        /// the known direction for a constant step, else both guarded by the
        /// runtime stride's sign.
        fn directed(self: Self, ascending: typed.NodeId, descending: typed.NodeId) diagnostic.Error!typed.NodeId {
            switch (self.stride) {
                .constant => |value| return if (value > 0) ascending else descending,
                .slot => |slot| {
                    const up = try self.b.binary(.logical_and, try self.compare(.gt, try self.b.read(slot), try self.zero()), ascending, .bool);
                    const down = try self.b.binary(.logical_and, try self.compare(.lt, try self.b.read(slot), try self.zero()), descending, .bool);
                    return self.b.binary(.logical_or, up, down, .bool);
                },
            }
        }
        /// Whether the counter still lies before `limit` in the step's direction.
        pub fn condition(self: Self, index: typed.LocalId, limit: typed.LocalId) diagnostic.Error!typed.NodeId {
            const ascending = try self.compare(.lt, try self.b.read(index), try self.b.read(limit));
            const descending = try self.compare(.gt, try self.b.read(index), try self.b.read(limit));
            return self.directed(ascending, descending);
        }
        /// Advance the counter by the step, or move it onto `limit` when the add
        /// wrapped past the end of the counter's type, which ends the loop.
        pub fn advance(self: Self, index: typed.LocalId, limit: typed.LocalId) diagnostic.Error!typed.StatementId {
            const b = self.b;
            const next = try b.local(self.element);
            const sum = try b.binary(.wrapping_add, try b.read(index), try self.step(), self.element);
            const below = try self.compare(.lt, try b.read(next), try b.read(index));
            const above = try self.compare(.gt, try b.read(next), try b.read(index));
            const wrapped = try self.directed(below, above);
            const finish = try b.stmt(.{ .assign = .{ .slot = index, .value = try b.read(limit) } });
            const proceed = try b.stmt(.{ .assign = .{ .slot = index, .value = try b.read(next) } });
            const statements = try b.checker.allocator.dupe(typed.StatementId, &.{
                try b.stmt(.{ .initialize = .{ .slot = next, .value = sum } }),
                try b.stmt(.{ .branch = .{ .condition = wrapped, .then_body = finish, .else_body = proceed } }),
            });
            return b.stmt(.{ .block = statements });
        }
        /// Hold a runtime stride in its local and trap a zero one before the
        /// loop starts; a constant stride needs neither.
        pub fn setup(self: Self, value: typed.NodeId) diagnostic.Error![]const typed.StatementId {
            const slot = switch (self.stride) {
                .constant => return &.{},
                .slot => |slot| slot,
            };
            const b = self.b;
            const nonzero = try self.compare(.ne, try b.read(slot), try self.zero());
            return b.checker.allocator.dupe(typed.StatementId, &.{
                try b.stmt(.{ .initialize = .{ .slot = slot, .value = value } }),
                try b.stmt(.{ .assertion = .{ .condition = nonzero, .message = zero_message } }),
            });
        }
    };
}

/// The stride of a checked step: its value when the checker knows it, else a
/// fresh local the caller initializes through `Lower.setup`. A literal zero is
/// rejected here with CPython's message.
pub fn stride(comptime Checker: type, b: collections.Builder(Checker), known: ?i128, element: typed.Type) diagnostic.Error!Stride {
    if (known) |value| {
        if (value == 0) return b.checker.sink.fail(zero_code, b.span, zero_message);
        return .{ .constant = value };
    }
    return .{ .slot = try b.local(element) };
}

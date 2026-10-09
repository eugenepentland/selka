//! Checked desugaring of the set vocabulary onto dictionary operations.
//!
//! A `set[T]` is a dictionary-kind collection from its elements to unit
//! (SET-1), so membership, `add`, `remove` and `discard` are the dictionary's
//! own expected-constant-time probes, and everything a set adds — literals,
//! the combining operators and the subset relations (SET-OPERATORS-1) — is
//! built here from the same checked locals, loops and dictionary operations
//! user code lowers to. No runtime support exists beyond `pop`'s removal of
//! the last entry.
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;
const Error = @import("diagnostic.zig").Error;
const collections = @import("collection_lower.zig");
const nominal = @import("nominal_catalog.zig");
const Catalog = @import("type_catalog.zig").Catalog;

/// Materialize `set[element]`.
pub fn setType(catalog: *Catalog, element: typed.Type, span: Span) Error!typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    const declaration = state.index.names.get("set") orelse return error.InternalError;
    return nominal.instantiateLengths(catalog, declaration, &.{element}, &.{}, span);
}

/// An operator or method that builds a new set from two: `|`/`union`,
/// `&`/`intersection`, `-`/`difference` and `^`/`symmetric_difference`.
pub const Combine = enum { @"union", intersection, difference, symmetric_difference };

/// A comparison between two sets: `<=`/`issubset`, `<`, `>=`/`issuperset`,
/// `>` and `isdisjoint`.
pub const Relation = enum { subset, proper_subset, superset, proper_superset, disjoint };

/// Diagnostic code for indexing a set, which has no positions or keyed values.
pub const index_code = "E_SET_INDEX";
/// Diagnostic code for `|`, `&` or `^` between two values that are not sets.
pub const bitwise_code = "E_SET_OPERATOR";

/// The integer builtin a set operator's spelling stands for, or null when
/// `spelling` is not `|`, `&` or `^`: integers keep `bit_or`, `bit_and` and
/// `bit_xor`, and only sets take the operator form.
pub fn bitwiseSpelling(spelling: []const u8) ?[]const u8 {
    if (spelling.len != 1) return null;
    return switch (spelling[0]) {
        '|' => "bit_or",
        '&' => "bit_and",
        '^' => "bit_xor",
        else => null,
    };
}

/// The set builders of one checker, over the ordinary checked-node builder.
pub fn Builder(comptime Checker: type) type {
    return struct {
        b: collections.Builder(Checker),
        const Self = @This();

        /// A fresh empty set of type `ty`: the dictionary constructor with no entries.
        pub fn empty(self: Self, ty: typed.Type) Error!typed.NodeId {
            return self.b.node(ty, .{ .array = &.{} });
        }
        /// The statement that adds `value` to the set held in `slot`: a
        /// dictionary write of unit, so a present element keeps its place.
        pub fn add(self: Self, slot: typed.LocalId, value: typed.NodeId) Error!typed.StatementId {
            const unit = try self.b.node(.unit, .unit);
            return self.b.stmt(.{ .discard = try self.b.operation(slot, .write, &.{ value, unit }) });
        }
        /// `{a, b, ...}`: a fresh set, then each element added in source order.
        pub fn literal(self: Self, ty: typed.Type, values: []const typed.NodeId) Error!typed.Node {
            const checker = self.b.checker;
            const owner = try self.b.local(ty);
            const statements = try checker.allocator.alloc(typed.StatementId, values.len + 1);
            statements[0] = try self.b.stmt(.{ .initialize = .{ .slot = owner, .value = try self.empty(ty) } });
            for (values, statements[1..]) |value, *statement| statement.* = try self.add(owner, value);
            return self.b.block(statements, try self.b.read(owner));
        }
        /// The statements of one walk over the keys of the dictionary-kind
        /// collection in `owner`, binding each to `element` and running
        /// `body`, in insertion order, while the optional `running` flag holds.
        /// The walk fixes its bound first and rechecks it before every step,
        /// exactly as a `for` loop over a dictionary does.
        pub fn walk(self: Self, owner: typed.LocalId, element: typed.LocalId, body: typed.StatementId, running: ?typed.LocalId) Error![3]typed.StatementId {
            const checker = self.b.checker;
            const index = try self.b.local(.i64);
            const limit = try self.b.local(.i64);
            const i = try self.b.read(index);
            const guard = try self.b.stmt(.{ .discard = try self.b.operation(owner, .iteration_check, &.{try self.b.read(limit)}) });
            const bind = try self.b.stmt(.{ .initialize = .{ .slot = element, .value = try self.b.operation(owner, .key_at, &.{i}) } });
            const iteration = try self.b.stmt(.{ .block = try checker.allocator.dupe(typed.StatementId, &.{ guard, bind, body }) });
            const advance = try self.b.stmt(.{ .assign = .{ .slot = index, .value = try self.b.binary(.add, i, try self.b.integer(1), .i64) } });
            const step = try self.b.stmt(.{ .block = try checker.allocator.dupe(typed.StatementId, &.{ guard, advance }) });
            var condition = try self.b.binary(.lt, i, try self.b.read(limit), .bool);
            if (running) |flag| condition = try self.b.binary(.logical_and, condition, try self.b.read(flag), .bool);
            const loop_id = checker.loops.next;
            checker.loops.next += 1;
            return .{
                try self.b.stmt(.{ .initialize = .{ .slot = index, .value = try self.b.integer(0) } }),
                try self.b.stmt(.{ .initialize = .{ .slot = limit, .value = try self.b.length(owner) } }),
                try self.b.stmt(.{ .loop = .{ .id = loop_id, .condition = condition, .body = iteration, .step = step } }),
            };
        }
        /// `left op right` for two sets of one type, each evaluated once, left
        /// first. The result is a fresh set holding the left operand's
        /// surviving elements in its order, then the right operand's new ones
        /// in theirs.
        pub fn combine(self: Self, op: Combine, left: typed.NodeId, right: typed.NodeId) Error!typed.Node {
            const checker = self.b.checker;
            const ty = checker.nodes.items[@backingInt(left)].ty;
            const key = checker.catalog.records[ty.recordIndex()].collection.key.?;
            const first = try self.b.local(ty);
            const second = try self.b.local(ty);
            const out = try self.b.local(ty);
            var statements: [10]typed.StatementId = undefined;
            var count: usize = 0;
            statements[count] = try self.b.stmt(.{ .initialize = .{ .slot = first, .value = left } });
            statements[count + 1] = try self.b.stmt(.{ .initialize = .{ .slot = second, .value = right } });
            count += 2;
            if (op == .@"union") {
                statements[count] = try self.b.stmt(.{ .initialize = .{ .slot = out, .value = try self.b.operation(first, .copy, &.{}) } });
                statements[count + 1] = try self.b.stmt(.{ .discard = try self.b.operation(out, .update, &.{try self.b.read(second)}) });
                return self.b.block(statements[0 .. count + 2], try self.b.read(out));
            }
            statements[count] = try self.b.stmt(.{ .initialize = .{ .slot = out, .value = try self.empty(ty) } });
            count += 1;
            // One walk over the left operand keeps what the right one holds
            // (intersection) or lacks (difference and the first half of the
            // symmetric difference).
            const kept = try self.filtered(.{ .source = first, .other = second, .out = out, .key = key, .present = op == .intersection });
            @memcpy(statements[count .. count + 3], &kept);
            count += 3;
            if (op == .symmetric_difference) {
                const rest = try self.filtered(.{ .source = second, .other = first, .out = out, .key = key, .present = false });
                @memcpy(statements[count .. count + 3], &rest);
                count += 3;
            }
            return self.b.block(statements[0..count], try self.b.read(out));
        }
        /// One filtered copy: every key of `source` whose membership in `other`
        /// equals `present` is added to `out`, in `source`'s order.
        const Filter = struct { source: typed.LocalId, other: typed.LocalId, out: typed.LocalId, key: typed.Type, present: bool };
        fn filtered(self: Self, filter: Filter) Error![3]typed.StatementId {
            const element = try self.b.local(filter.key);
            const test_value = try self.membership(filter.other, element, filter.present);
            const body = try self.b.stmt(.{ .branch = .{ .condition = test_value, .then_body = try self.add(filter.out, try self.b.read(element)), .else_body = null } });
            return self.walk(filter.source, element, body, null);
        }
        /// Whether the key in `element` is (`present`) or is not in the set in `slot`.
        fn membership(self: Self, slot: typed.LocalId, element: typed.LocalId, present: bool) Error!typed.NodeId {
            const found = try self.b.operation(slot, .contains, &.{try self.b.read(element)});
            if (present) return found;
            return self.b.node(.bool, .{ .unary = .{ .op = .not, .operand = found, .op_span = self.b.span } });
        }
        /// `left op right` for a subset relation or `isdisjoint`, each operand
        /// evaluated once, left first. The walk stops at the first key that
        /// settles the answer, and a subset test whose sizes already rule it
        /// out never walks at all.
        pub fn relation(self: Self, op: Relation, left: typed.NodeId, right: typed.NodeId) Error!typed.Node {
            const checker = self.b.checker;
            const ty = checker.nodes.items[@backingInt(left)].ty;
            const key = checker.catalog.records[ty.recordIndex()].collection.key.?;
            const first = try self.b.local(ty);
            const second = try self.b.local(ty);
            const swapped = op == .superset or op == .proper_superset;
            const inner = if (swapped) second else first;
            const outer = if (swapped) first else second;
            const holds = try self.b.local(.bool);
            const initial = if (op == .disjoint)
                try self.b.node(.bool, .{ .boolean = true })
            else
                try self.b.binary(.le, try self.b.length(inner), try self.b.length(outer), .bool);
            const element = try self.b.local(key);
            // A subset fails at the first inner key the outer set lacks; two
            // sets stop being disjoint at the first inner key the outer holds.
            const settles = try self.membership(outer, element, op == .disjoint);
            const refuted = try self.b.stmt(.{ .assign = .{ .slot = holds, .value = try self.b.node(.bool, .{ .boolean = false }) } });
            const body = try self.b.stmt(.{ .branch = .{ .condition = settles, .then_body = refuted, .else_body = null } });
            const loop = try self.walk(inner, element, body, holds);
            var answer = try self.b.read(holds);
            if (op == .proper_subset or op == .proper_superset)
                answer = try self.b.binary(.logical_and, answer, try self.b.binary(.lt, try self.b.length(inner), try self.b.length(outer), .bool), .bool);
            return self.b.block(&.{
                try self.b.stmt(.{ .initialize = .{ .slot = first, .value = left } }),
                try self.b.stmt(.{ .initialize = .{ .slot = second, .value = right } }),
                try self.b.stmt(.{ .initialize = .{ .slot = holds, .value = initial } }),
                loop[0],
                loop[1],
                loop[2],
            }, answer);
        }
    };
}

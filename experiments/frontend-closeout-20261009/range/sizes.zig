const std = @import("std");
const typed = @import("typed");
const Span = @FieldType(typed.Statement, "span");
const LocalId = typed.LocalId;
const NodeId = typed.NodeId;
const StatementId = typed.StatementId;
const Store = typed.Store;
const MatchArm = typed.MatchArm;
const Assertion = typed.Assertion;
const PriorStatement = struct {
    span: Span,
    terminates: bool,
    data: union(enum) {
        with_scope: struct { slot: LocalId, resource: ?NodeId, body: StatementId },
        block: []const StatementId,
        assertion: Assertion,
        ret: NodeId,
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm, borrowed: bool = false },
        loop: struct { id: usize = 0, condition: NodeId, body: StatementId, step: ?StatementId = null },
        loop_exit: struct { target: usize, continuing: bool },
        initialize: Store,
        assign: Store,
    },
};
pub fn main() void { std.debug.print("old_statement_bytes={d} new_statement_bytes={d} range_parts_bytes={d} range_payload_bytes={d}\n", .{@sizeOf(PriorStatement),@sizeOf(typed.Statement),@sizeOf(typed.RangeParts),@sizeOf(typed.RangeLoop)}); }

//! A comparison chain as control flow (proof steps, lane C, D-S2-9).
//!
//! The checker desugars `a <= x < b` (`sema_idioms.chainBlock`, PY-CHAIN-1) into a block expression: a slot per operand but
//! the last, and a `bool` result assigned link by link under nested `if`s, read as the block's value:
//!
//!     { s0 = a; { s1 = x; r = s0 <= s1; if r: { r = s1 < b } } } -> r
//!
//! Evaluated as a value, `r` reaches a branch through a phi, which no refining branch edge reads, so a test of `x` against
//! both bounds narrows nothing beyond it. `branchOn` lowers such a block, where it is a condition, as one branch per link on
//! that link's own comparison, the way it lowers `and`: the same statements in the same order (each operand evaluated once,
//! a later operand only after every earlier link held), with the branch on `r` replaced by a branch on the comparison
//! stored into it. `r` is then never written or read. Only chains whose operand slots are integers or booleans are split:
//! a managed or float operand keeps the value lowering, and so does a chain used as a value (`const ok = a < x < b`).
const typed = @import("selka").typed;
const ir = @import("ir.zig");

/// What lowering a chain can fail with: the builder's own errors (`build.Error`).
pub const Error = error{ OutOfMemory, Unsupported };

/// A recognized chain: the statement that initializes the first slot and the block of the first link.
pub const Chain = struct { first: typed.StatementId, link: typed.StatementId, result: typed.LocalId };

/// One link's block: an optional initialization of the next operand's slot, the store of the comparison into the result,
/// and the `if` on the result that leads to the next link (absent on the last).
const Link = struct { operand: ?typed.StatementId, comparison: typed.NodeId, next: ?typed.StatementId };

/// The chain `node` is, in exactly the form `chainBlock` builds, or null.
pub fn of(comptime Builder: type, self: Builder, node: typed.NodeId) ?Chain {
    const n = self.nodeOf(node);
    if (n.ty != .bool) return null;
    const block = switch (n.data) {
        .block_value => |value| value,
        else => return null,
    };
    const result = switch (self.nodeOf(block.value).data) {
        .local => |slot| slot,
        else => return null,
    };
    const items = switch (self.nodeOfStatement(block.body).data) {
        .block => |statements| statements,
        else => return null,
    };
    if (items.len != 2) return null;
    const first = initialized(Builder, self, items[0]) orelse return null;
    if (first == result or !scalar(Builder, self, first)) return null;
    // Walk every link once to accept the whole shape before anything is lowered.
    var at: ?typed.StatementId = items[1];
    var index: usize = 0;
    while (at) |current| : (index += 1) {
        const link = linkOf(Builder, self, current, result, index == 0) orelse return null;
        if (link.operand) |operand| {
            const slot = initialized(Builder, self, operand) orelse return null;
            if (slot == result or !scalar(Builder, self, slot)) return null;
        }
        at = link.next;
    }
    if (index < 2) return null;
    return .{ .first = items[0], .link = items[1], .result = result };
}

/// Lower `chain` as a condition: to `then` when every link holds, to `otherwise` at the first that fails. The caller seals
/// `then` and `otherwise`, as for `branchOn`.
pub fn branchOn(comptime Builder: type, self: Builder, chain: Chain, targets: struct { then: ir.BlockId, otherwise: ir.BlockId, span: u32 }) Error!void {
    try self.statement(chain.first);
    var at: ?typed.StatementId = chain.link;
    var first = true;
    while (at) |current| {
        const link = linkOf(Builder, self, current, chain.result, first).?;
        first = false;
        if (link.operand) |operand| try self.statement(operand);
        if (self.current == null) return;
        const holds = try self.expression(link.comparison);
        if (self.current == null) return;
        const next = link.next orelse return self.branch(holds, targets.then, targets.otherwise, targets.span);
        const middle = try self.newBlock();
        try self.branch(holds, middle, targets.otherwise, targets.span);
        try self.seal(middle);
        self.current = middle;
        at = next;
    }
}

fn linkOf(comptime Builder: type, self: Builder, id: typed.StatementId, result: typed.LocalId, first: bool) ?Link {
    const parts = switch (self.nodeOfStatement(id).data) {
        .block => |statements| statements,
        else => return null,
    };
    if (parts.len != 1 and parts.len != 3) return null;
    const store_at = if (parts.len == 3) parts[1] else parts[0];
    const comparison = resultStore(Builder, self, store_at, result, first) orelse return null;
    if (parts.len == 1) return .{ .operand = null, .comparison = comparison, .next = null };
    const test_ = switch (self.nodeOfStatement(parts[2]).data) {
        .branch => |b| b,
        else => return null,
    };
    if (test_.else_body != null) return null;
    switch (self.nodeOf(test_.condition).data) {
        .local => |slot| if (slot != result) return null,
        else => return null,
    }
    return .{ .operand = parts[0], .comparison = comparison, .next = test_.then_body };
}

/// The comparison stored into `result` by statement `id`: an initialization on the first link, an assignment after it.
fn resultStore(comptime Builder: type, self: Builder, id: typed.StatementId, result: typed.LocalId, first: bool) ?typed.NodeId {
    const store = switch (self.nodeOfStatement(id).data) {
        .initialize => |s| if (first) s else return null,
        .assign => |s| if (!first) s else return null,
        else => return null,
    };
    if (store.slot != result or store.unpack != null or store.element or store.transfer) return null;
    if (self.nodeOf(store.value).ty != .bool) return null;
    return store.value;
}

/// The slot a plain initialization statement writes.
fn initialized(comptime Builder: type, self: Builder, id: typed.StatementId) ?typed.LocalId {
    const store = switch (self.nodeOfStatement(id).data) {
        .initialize => |s| s,
        else => return null,
    };
    if (store.unpack != null or store.element or store.transfer) return null;
    return store.slot;
}

/// Whether an operand slot holds an integer or a boolean, which no cleanup or ownership step follows.
fn scalar(comptime Builder: type, self: Builder, slot: typed.LocalId) bool {
    return switch (self.checked.scope.locals[@backingInt(slot)].ty) {
        .i64, .bool, .i8, .i16, .i32, .u8, .u16, .u32, .u64 => true,
        else => false,
    };
}

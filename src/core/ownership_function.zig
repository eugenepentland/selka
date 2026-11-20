//! One function as an ownership certificate states it (docs/design/ownership-certificates.md §4.1), in memory.
//!
//! The exporter builds this from the final IR, the operation table and the table the ownership pass kept; the
//! text writer prints it line for line; the validator checks it. It is the only thing the validator reads, so
//! the validator and the Lean checker see the same facts, and it imports nothing of the ownership pass.
const std = @import("std");
const ir = @import("ir.zig");
const ops = @import("ownership_ops.zig");
const certificate = @import("ownership_certificate.zig");

/// The ownership state of a value (design §2).
pub const State = certificate.State;

/// Why a function carries no checkable certificate. The validator skips and counts these; none ever counts as
/// validated. Since C6 the exporter produces no reason (design §10): the reader still accepts the ones an earlier
/// exporter wrote.
pub const Reason = enum {
    /// A file written before C6 marks a function that uses a task group or a lent box with this reason (design §4).
    task_group,

    /// The spelling in the format.
    pub fn token(self: Reason) []const u8 {
        return switch (self) {
            .task_group => "task-group",
        };
    }
};

/// A parent of a borrowed value: another value of the function, or the allocation behind a borrowed
/// parameter of the caller.
pub const Parent = union(enum) { value: u32, caller: u32 };

/// What a line states of the value it defines.
pub const Result = struct {
    state: State,
    parents: []const Parent = &.{},
};

/// The parts of a dictionary entry or of an overwritten slot a store destroys (`released`) or finds already moved
/// out by a take (`taken`).
pub const Parts = packed struct {
    /// The old content of a list element, an element field or a dictionary value that a store replaces.
    old: bool = false,
    /// The key of a dictionary entry `dict_remove` removes.
    key: bool = false,
    /// The value of a dictionary entry `dict_remove` removes.
    value: bool = false,
};

/// The extras of a `call` or `call_indirect` line (design §9, entry 57).
pub const Call = struct {
    /// The values the callee's `from` contract says the result may borrow from.
    from: ?[]const u32 = null,
    /// The entry of the function's callee table this call names.
    callee: ?u32 = null,
};

/// The extras of an `inst` line that concern the loans an instruction hands on (design §10, §5 J4).
pub const Loans = struct {
    /// For a `box_make` that lends its first operand to a task group: the group, which is its second operand.
    lent: ?u32 = null,
    /// For a take whose result type cannot hold a view: the part it takes out carries no loans of the aggregate it leaves.
    noloans: bool = false,
    /// For a constructor with an owned or `emptied` result: the borrowed operands it reads into a slot whose type its
    /// destruction does not destroy (a span, a list view, a borrowed overlay, a record of those). Only these may be a loan
    /// the aggregate holds (J6 `construct-read`, condition 2). Empty when it reads none.
    views: []const u32 = &.{},
};

/// The optional tail of an `inst` line (design §4.1, Extras), in print order.
pub const Extras = struct {
    /// The slot a container instruction reads, takes or stores: `f<k>`, `e<I>[p<steps>]`, `k<I>`, `v<I>` or `tail`.
    slot: ?[]const u8 = null,
    /// What a store destroys of the content it replaces or removes.
    released: ?Parts = null,
    /// What a `dict_remove` finds already moved out by a take.
    taken: ?Parts = null,
    /// The managed fields of an `emptied` record, each taken exactly once.
    slots: ?[]const []const u8 = null,
    /// What a call line says of its callee.
    call: Call = .{},
    /// What an instruction does with loans: a lend, and a take that hands none on.
    loans: Loans = .{},
    /// For `iconst`, `cmp` and `fcmp`: the instruction's `data` (the constant, or the predicate), so that two branches on
    /// the same test can be recognised (design §4.1, guards).
    imm: ?u64 = null,
};

/// One `inst` line.
pub const Inst = struct {
    /// The value the instruction defines; null for `inst -`.
    value: ?u32,
    op: ir.Op,
    class: ops.Class,
    reads: []const u32,
    consumes: []const u32,
    result: Result,
    extras: Extras = .{},
};

/// One incoming edge of a phi.
pub const Edge = struct { block: u32, value: u32 };

/// One `phi` line.
pub const Phi = struct {
    value: u32,
    result: Result,
    edges: []const Edge,
};

/// A block's last line.
pub const Term = union(enum) {
    jump: u32,
    branch: struct { condition: u32, then: u32, otherwise: u32 },
    ret: ?u32,
    unreachable_path,
};

/// The owners a trap path abandons on the edge from block `from` into a block every path of which ends in a trap (design §9,
/// entry 55): live on the edge, needed by nothing from the block on, and never destroyed because the process ends. Values ascend.
pub const Abandon = struct { from: u32, values: []const u32 };

/// A block as the file lists it: the blocks the emitter skips are not listed.
pub const Block = struct {
    id: u32,
    preds: []const u32,
    /// The `abandon` lines, by predecessor (trap-region blocks only).
    abandons: []const Abandon = &.{},
    phis: []const Phi,
    insts: []const Inst,
    term: Term,
};

/// A parameter line: the value that names it and the state the signature gives it.
pub const Param = struct { value: u32, state: State };

/// What a function returns, from its signature.
pub const ResultKind = enum { scalar, owned, borrowed };

/// What a callee table entry says of the callee (design §9, entry 57).
pub const CalleeKind = enum {
    /// A function of the program: its entry is linked to its `function` line by name.
    program,
    /// A `myl_core_*` runtime function (assumption A5).
    runtime,
    /// An `extern func` (A5).
    @"extern",
    /// A reserved marker call (design §3).
    marker,
    /// A call through a function value: the entry is the function type's signature.
    indirect,

    /// The spelling in the format.
    pub fn token(self: CalleeKind) []const u8 {
        return @tagName(self);
    }
};

/// How a callee takes one parameter, and the state its own `param` line gives that parameter.
pub const ParamMode = enum {
    /// Consumed; the state is owned.
    take,
    /// Consumed; an unmanaged parameter, the state is scalar.
    take_scalar,
    /// Read only; the state is borrowed.
    read,
    /// Read only; an unmanaged parameter, the state is scalar.
    read_scalar,

    /// The spelling in the format.
    pub fn token(self: ParamMode) []const u8 {
        return switch (self) {
            .take => "take",
            .take_scalar => "take-scalar",
            .read => "read",
            .read_scalar => "read-scalar",
        };
    }

    /// Whether the argument is in `consumes`.
    pub fn consumed(self: ParamMode) bool {
        return self == .take or self == .take_scalar;
    }

    /// Whether the state the callee's `param` line gives is scalar.
    pub fn scalar(self: ParamMode) bool {
        return self == .take_scalar or self == .read_scalar;
    }
};

/// One line of a function's callee table.
pub const Callee = struct {
    id: u32,
    /// The callee's name as its `function` line spells it; empty for an indirect call.
    name: []const u8,
    kind: CalleeKind,
    params: []const ParamMode,
    result: ResultKind,
    from: []const u32,
};

/// What a function returns, from its signature: the kind, and the parameters a borrowed result may borrow from.
pub const Returns = struct { kind: ResultKind, from: []const u32 };

/// One function of a certificate file.
pub const Function = struct {
    name: []const u8,
    returns: Returns,
    unchecked: ?Reason,
    params: []const Param,
    /// The callees of its calls, by the id the call lines name.
    callees: []const Callee = &.{},
    /// The pseudo-block `b-`: parameters and constants.
    pre: []const Inst,
    blocks: []const Block,
};

//! One module as a fact certificate states it (docs/design/fact-certificates.md §10), in memory.
//!
//! The exporter builds this from the final IR and the fact tables the passes kept; the text writer prints it line for
//! line; the parser reads it back; the validator checks it. It is the only thing the validator reads, so the validator
//! and the Lean checker see the same facts, and it imports nothing of the fact pass.
const std = @import("std");
const ir = @import("ir.zig");

/// The largest list or string the address space holds (design §4, `M`; `target.zig` states the same number).
pub const max_list_length: i128 = 1 << 47;

/// A closed integer interval, exact in `i128` (design §3).
pub const Interval = struct {
    lo: i128,
    hi: i128,

    /// The interval holding exactly `value`.
    pub fn point(value: i128) Interval {
        return .{ .lo = value, .hi = value };
    }
    /// The smallest interval holding both.
    pub fn hull(a: Interval, b: Interval) Interval {
        return .{ .lo = @min(a.lo, b.lo), .hi = @max(a.hi, b.hi) };
    }
    /// The values both hold (empty when `lo > hi`).
    pub fn meet(a: Interval, b: Interval) Interval {
        return .{ .lo = @max(a.lo, b.lo), .hi = @min(a.hi, b.hi) };
    }
    /// Whether every value of `self` lies in `other`; the empty interval lies in every interval.
    pub fn within(self: Interval, other: Interval) bool {
        return self.empty() or (self.lo >= other.lo and self.hi <= other.hi);
    }
    /// Whether no value lies in it.
    pub fn empty(self: Interval) bool {
        return self.lo > self.hi;
    }
};

/// The type of a value as the certificate classifies it (design §10, Types).
pub const Type = enum {
    void,
    bool,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f64,
    list,
    other,

    /// The spelling in the format.
    pub fn token(self: Type) []const u8 {
        return @tagName(self);
    }

    /// The type a spelling names.
    pub fn fromToken(text: []const u8) ?Type {
        return std.meta.stringToEnum(Type, text);
    }

    /// Whether the type is an integer or a boolean: the values that carry intervals.
    pub fn isInteger(self: Type) bool {
        return self.range() != null;
    }

    /// Width in bits of an integer type, 1 for `bool`; 0 for any other type.
    pub fn bits(self: Type) u16 {
        return switch (self) {
            .bool => 1,
            .i8, .u8 => 8,
            .i16, .u16 => 16,
            .i32, .u32 => 32,
            .i64, .u64 => 64,
            else => 0,
        };
    }

    /// Whether the integer type is signed.
    pub fn signed(self: Type) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64 => true,
            else => false,
        };
    }

    /// Every value the type holds, or null for a non-integer type (design §2.1, `R(t)`).
    pub fn range(self: Type) ?Interval {
        const width = self.bits();
        if (width == 0) return null;
        if (self == .bool) return .{ .lo = 0, .hi = 1 };
        if (self.signed()) return .{ .lo = -(@as(i128, 1) << @intCast(width - 1)), .hi = (@as(i128, 1) << @intCast(width - 1)) - 1 };
        return .{ .lo = 0, .hi = (@as(i128, 1) << @intCast(width)) - 1 };
    }
};

/// The operands of an instruction line: the IR's two operands and its extra list, after `copy` resolution. For a
/// `call`, `a` is the callee's function index.
pub const Operands = struct {
    a: ?u32 = null,
    b: ?u32 = null,
    x: []const u32 = &.{},
};

/// The immediates of an instruction line: the instruction's `data` (the constant's bits, the predicate, a field), and
/// the array length of `array_get`/`array_set`.
pub const Immediates = struct {
    imm: u64 = 0,
    aux: u64 = 0,
};

/// One `inst` line.
pub const Inst = struct {
    value: u32,
    op: ir.Op,
    ty: Type,
    check: ir.Check,
    operands: Operands = .{},
    immediates: Immediates = .{},
    /// The interval the facts state for the value; null makes no claim.
    range: ?Interval = null,
};

/// One incoming edge of a phi.
pub const Edge = struct { block: u32, value: u32 };

/// One `phi` line.
pub const Phi = struct {
    value: u32,
    ty: Type,
    edges: []const Edge,
    range: ?Interval = null,
};

/// How a block ends.
pub const Term = union(enum) {
    jump: u32,
    branch: struct { condition: u32, then: u32, otherwise: u32 },
    ret: ?u32,
    unreachable_path,
};

/// One block: its predecessors in the order the phis list their edges, its phis, its instructions and its end.
pub const Block = struct {
    id: u32,
    dead: bool,
    preds: []const u32,
    phis: []const Phi,
    insts: []const Inst,
    term: Term,
};

/// A builder loop record (`ir.Loop`): the validator recognises counted loops on these.
pub const Loop = struct { header: u32, body: u32, latch: u32, exit: u32 };

/// What the facts state of a list value (design §2.4).
pub const ListFact = struct {
    value: u32,
    len: ?Interval = null,
    elems: ?Interval = null,
    /// The fill length: the value of the bound of the counted fill loop the list comes from.
    length: ?u32 = null,
    pattern: bool = false,
};

/// `value <= len(list)`, or `<` when strict, for a list parameter.
pub const Bound = struct { value: u32, list: u32, strict: bool };

/// The viewed operand intervals of one `proven` instruction (design §10, Sites), in the order the format fixes.
pub const Site = struct { value: u32, parts: []const ?Interval };

/// The facts a function states beyond its instructions' intervals.
pub const Aux = struct {
    loops: []const Loop = &.{},
    lists: []const ListFact = &.{},
    bounds: []const Bound = &.{},
    sites: []const Site = &.{},
};

/// The function header.
pub const Header = struct {
    name: []const u8,
    internal: bool,
    address_taken: bool,
    params: []const Type,
    ret: Type,
};

/// What a function states about its parameters and what it returns (design §2.3).
pub const Boundary = struct {
    /// Per parameter, the interval every caller's argument lies in.
    params: []const ?Interval = &.{},
    returns: ?Interval = null,
};

/// One function.
pub const Function = struct {
    header: Header,
    boundary: Boundary = .{},
    /// Constants and parameters, defined outside every block.
    pre: []const Inst = &.{},
    blocks: []const Block = &.{},
    aux: Aux = .{},
};

/// The certificate of one module: every function with a body, in module order.
pub const Module = struct {
    functions: []const Function,
};
